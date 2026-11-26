#ifndef MSTNGM5EA_PERSISTENCE_DATABASECONTEXT_MQH
#define MSTNGM5EA_PERSISTENCE_DATABASECONTEXT_MQH

#include <Mstng\Database\SqliteDatabase.mqh>
#include <MstngM5Ea\Persistence\M5EaDecisionDao.mqh>
#include <MstngM5Ea\Persistence\M5EaRunDao.mqh>
#include <MstngM5Ea\Persistence\M5EaTradeDao.mqh>
#include <MstngM5Ea\Persistence\M5EaTradeEventDao.mqh>

/**
 * M5専用DBの物理schema v1を作成・厳密照合する。
 * H1 DBや未知schemaは変更せず拒否し、既存schemaの自動移行は行わない。
 */
class M5EaDatabaseContext {
public:
    /**
     * 未接続状態で初期化する。
     */
    M5EaDatabaseContext() {
        this.database = NULL;
    }

    /**
     * 接続を解放する。
     */
    ~M5EaDatabaseContext() {
        this.close();
    }

    /**
     * Common内のM5 DBだけを開く。再接続時はDDLを禁止する。
     */
    bool open(const string fromFileName, const bool fromInitializeSchema = true) {
        this.close();

        this.database = new SqliteDatabase(fromFileName, true);
        if (this.database == NULL || !this.database.open()) {
            this.close();
            return false;
        }

        long version = 0;
        long objects = 0;
        if (!M5EaSql::scalar(this.getHandle(), "PRAGMA user_version", version)
                || !this.countSchemaObjects(objects)) {
            this.close();
            return false;
        }

        bool emptyDatabase = version == 0 && objects == 0;
        // 未知DBにはjournal modeやschemaを一切書き込まない。
        if ((emptyDatabase && !fromInitializeSchema)
                || (!emptyDatabase && (version != 1 || !this.validateSchema()))) {
            this.close();
            return false;
        }

        if (!M5EaSql::execute(this.getHandle(), "PRAGMA foreign_keys=ON")
                || !M5EaSql::execute(this.getHandle(), "PRAGMA busy_timeout=5000")
                || !M5EaSql::execute(this.getHandle(), "PRAGMA journal_mode=WAL")) {
            this.close();
            return false;
        }

        long foreignKeys = 0;
        long timeout = 0;
        string journalMode = "";
        if (!M5EaSql::scalar(this.getHandle(), "PRAGMA foreign_keys", foreignKeys)
                || !M5EaSql::scalar(this.getHandle(), "PRAGMA busy_timeout", timeout)
                || !this.readText("PRAGMA journal_mode", journalMode)
                || foreignKeys != 1 || timeout != 5000 || journalMode != "wal"
                || (emptyDatabase && !this.createSchema())) {
            this.close();
            return false;
        }

        return true;
    }

    /**
     * 接続だけを閉じる。DBファイルは削除しない。
     */
    void close() {
        if (this.database != NULL) {
            this.database.close();
            delete this.database;
            this.database = NULL;
        }
    }

    /**
     * 接続ハンドルを返す。
     */
    int getHandle() const {
        if (this.database == NULL) {
            return INVALID_HANDLE;
        }

        return this.database.getHandle();
    }

private:
    /** M5専用SQLite接続。 */
    SqliteDatabase *database;

    /**
     * 全schema要素のSQLを一つの順序付き配列へ集める。
     */
    bool schemaSql(string &fromSql[]) {
        if (ArrayResize(fromSql, 4) != 4) {
            return false;
        }

        fromSql[0] = M5EaRunDao::createSql();
        fromSql[1] = M5EaDecisionDao::createSql();
        fromSql[2] = M5EaTradeDao::createSql();
        fromSql[3] = M5EaTradeEventDao::createSql();
        string indices[];

        return M5EaRunDao::indexSql(indices) && this.appendSql(fromSql, indices)
            && M5EaDecisionDao::indexSql(indices) && this.appendSql(fromSql, indices)
            && M5EaTradeDao::indexSql(indices) && this.appendSql(fromSql, indices)
            && M5EaTradeEventDao::indexSql(indices) && this.appendSql(fromSql, indices);
    }

    /**
     * SQL配列を伸長できた場合だけ末尾へ追加する。
     */
    bool appendSql(string &fromTarget[], const string &fromSource[]) {
        int offset = ArraySize(fromTarget);
        int size = offset + ArraySize(fromSource);
        if (ArrayResize(fromTarget, size) != size) {
            return false;
        }

        for (int i = 0; i < ArraySize(fromSource); i++) {
            fromTarget[offset + i] = fromSource[i];
        }

        return true;
    }

    /**
     * SQLite内部要素を除いた全要素を数える。
     */
    bool countSchemaObjects(long &fromCount) {
        return M5EaSql::scalar(this.getHandle(),
            "SELECT COUNT(*) FROM sqlite_schema WHERE name NOT GLOB 'sqlite_*'", fromCount);
    }

    /**
     * 一件の文字列を取得する。
     */
    bool readText(const string fromSql, string &fromText) {
        int request = DatabasePrepare(this.getHandle(), fromSql);
        if (request == INVALID_HANDLE) {
            return false;
        }

        bool success = DatabaseRead(request) && DatabaseColumnText(request, 0, fromText);
        DatabaseFinalize(request);

        return success;
    }

    /**
     * 同じversion番号でも列・制約・索引の欠落や追加を拒否する。
     */
    bool validateSchema() {
        string statements[];
        long count = 0;
        if (!this.schemaSql(statements) || !this.countSchemaObjects(count)
                || count != ArraySize(statements)) {
            return false;
        }

        for (int i = 0; i < ArraySize(statements); i++) {
            string expected = statements[i];
            string marker = "IF NOT EXISTS ";
            int nameStart = StringFind(expected, marker) + StringLen(marker);
            int nameEnd = StringFind(expected, " ", nameStart);
            if (nameStart < StringLen(marker) || nameEnd <= nameStart) {
                return false;
            }

            string name = StringSubstr(expected, nameStart, nameEnd - nameStart);
            string actual = "";
            if (!this.readText("SELECT sql FROM sqlite_schema WHERE name="
                    + M5EaSql::text(name), actual)) {
                return false;
            }

            StringReplace(expected, marker, "");
            StringReplace(actual, marker, "");
            StringReplace(expected, ";", "");
            StringReplace(actual, ";", "");
            if (actual != expected) {
                return false;
            }
        }

        return true;
    }

    /**
     * 空DBへ全要素を原子的に作成する。途中失敗は必ずrollbackする。
     */
    bool createSchema() {
        string statements[];
        if (!this.schemaSql(statements)
                || !M5EaSql::execute(this.getHandle(), "BEGIN IMMEDIATE")) {
            return false;
        }

        bool success = true;
        for (int i = 0; i < ArraySize(statements); i++) {
            if (!M5EaSql::execute(this.getHandle(), statements[i])) {
                success = false;
                break;
            }
        }

        if (success && this.validateSchema()
                && M5EaSql::execute(this.getHandle(), "PRAGMA user_version=1")
                && M5EaSql::execute(this.getHandle(), "COMMIT")) {
            return true;
        }

        M5EaSql::execute(this.getHandle(), "ROLLBACK");

        return false;
    }
};

#endif
