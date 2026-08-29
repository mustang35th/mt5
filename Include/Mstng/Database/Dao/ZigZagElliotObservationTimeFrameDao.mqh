//+------------------------------------------------------------------+
//|                          ZigZagElliotObservationTimeFrameDao.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_OBSERVATION_TF_DAO_MQH
#define MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_OBSERVATION_TF_DAO_MQH

#include <Mstng\Database\Dao\ZigZagElliotObservationAddedPointMigration.mqh>
#include <Mstng\Database\Dao\ZigZagElliotObservationJstMigration.mqh>
#include <Mstng\Database\Entity\ZigZagElliotObservationTimeFrameEntity.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * ZigZagElliot観測の時間足別分析をSQLiteへ保存するDAO。
 */
class ZigZagElliotObservationTimeFrameDao {
public:
    /**
     * データベースハンドルを指定して初期化する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     */
    ZigZagElliotObservationTimeFrameDao(const int fromDatabaseHandle) {
        this.databaseHandle = fromDatabaseHandle;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 時間足別観測テーブルと検索用インデックスを作成する。
     *
     * @return 作成に成功した場合true。
     */
    bool createTable() {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "CREATE TABLE IF NOT EXISTS ";
        sql += "zigzag_elliot_observation_timeframes (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "observation_id INTEGER NOT NULL,";
        sql += "time_frame INTEGER NOT NULL,";
        sql += "time_frame_text TEXT NOT NULL,";
        sql += "time_frame_order INTEGER NOT NULL CHECK(time_frame_order >= 0),";
        sql += "is_anchor_time_frame INTEGER NOT NULL ";
        sql += "CHECK(is_anchor_time_frame IN (0, 1)),";
        sql += "is_buy INTEGER NOT NULL CHECK(is_buy IN (0, 1)),";
        sql += "buy_sell_label TEXT NOT NULL,";
        sql += "wave_count INTEGER NOT NULL,";
        sql += "latest_wave_index INTEGER NOT NULL,";
        sql += "is_wave_confirmed INTEGER NOT NULL ";
        sql += "CHECK(is_wave_confirmed IN (0, 1)),";
        sql += "is_wave_motive INTEGER NOT NULL ";
        sql += "CHECK(is_wave_motive IN (0, 1)),";
        sql += "is_wave_uptrend INTEGER NOT NULL ";
        sql += "CHECK(is_wave_uptrend IN (0, 1)),";
        sql += "wave_trend_label TEXT NOT NULL,";
        sql += "previous_last_elliot_label TEXT NOT NULL,";
        sql += "point_count INTEGER NOT NULL CHECK(point_count > 0),";
        sql += "latest_elliot_index INTEGER NOT NULL,";
        sql += "latest_elliot_label TEXT NOT NULL,";
        sql += "latest_sub_elliot_index INTEGER NOT NULL,";
        sql += "latest_sub_elliot_label TEXT NOT NULL,";
        sql += "latest_point_time INTEGER NOT NULL CHECK(latest_point_time > 0),";
        sql += "latest_point_time_text TEXT NOT NULL,";
        sql += "latest_point_jst_time INTEGER NOT NULL ";
        sql += "CHECK(latest_point_jst_time > 0),";
        sql += "latest_point_jst_time_text TEXT NOT NULL,";
        sql += "latest_point_rate REAL NOT NULL,";
        sql += "latest_point_is_added INTEGER ";
        sql += "CHECK(latest_point_is_added IS NULL ";
        sql += "OR latest_point_is_added IN (0, 1)),";
        sql += "previous_open REAL NOT NULL,";
        sql += "previous_high REAL NOT NULL,";
        sql += "previous_low REAL NOT NULL,";
        sql += "previous_close REAL NOT NULL,";
        sql += "current_open REAL NOT NULL,";
        sql += "current_high REAL NOT NULL,";
        sql += "current_low REAL NOT NULL,";
        sql += "current_close REAL NOT NULL,";
        sql += "is_fibo_expansion_available INTEGER NOT NULL ";
        sql += "CHECK(is_fibo_expansion_available IN (0, 1)),";
        sql += "fe618_price REAL NOT NULL,";
        sql += "fe1000_price REAL NOT NULL,";
        sql += "fe1272_price REAL NOT NULL,";
        sql += "fe1618_price REAL NOT NULL,";
        sql += "fe2000_price REAL NOT NULL,";
        sql += "distance_to_fe2000_pips REAL NOT NULL,";
        sql += "oscillator_count INTEGER NOT NULL,";
        sql += "is_oscillator_buy INTEGER NOT NULL ";
        sql += "CHECK(is_oscillator_buy IN (0, 1)),";
        sql += "stochastic_main_order INTEGER NOT NULL,";
        sql += "stochastic_main_order_text TEXT NOT NULL,";
        sql += "stochastic_main_direction_text TEXT NOT NULL,";
        sql += "stochastic_short_count INTEGER NOT NULL,";
        sql += "stochastic_short_main REAL NOT NULL,";
        sql += "stochastic_short_signal REAL NOT NULL,";
        sql += "stochastic_middle_count INTEGER NOT NULL,";
        sql += "stochastic_middle_main REAL NOT NULL,";
        sql += "stochastic_middle_signal REAL NOT NULL,";
        sql += "stochastic_long_count INTEGER NOT NULL,";
        sql += "stochastic_long_main REAL NOT NULL,";
        sql += "stochastic_long_signal REAL NOT NULL,";
        sql += "gmma_trend_count INTEGER NOT NULL,";
        sql += "gmma_cross_count INTEGER NOT NULL,";
        sql += "ema30 REAL NOT NULL,";
        sql += "ema60 REAL NOT NULL,";
        sql += "ema30_ema60_diff_pips REAL NOT NULL,";
        sql += "atr14_pips REAL NOT NULL,";
        sql += "ema200_close1 REAL NOT NULL,";
        sql += "ema200_shift1 REAL NOT NULL,";
        sql += "ema200_compare REAL NOT NULL,";
        sql += "ema200_slope_pips REAL NOT NULL,";
        sql += "ema200_close_diff_pips REAL NOT NULL,";
        sql += "ema200_close_position INTEGER NOT NULL,";
        sql += "ema200_slope_direction INTEGER NOT NULL,";
        sql += "ema200_up_count INTEGER NOT NULL,";
        sql += "ema200_down_count INTEGER NOT NULL,";
        sql += "ema200_trend_count INTEGER NOT NULL,";
        sql += "is_ema200_buy INTEGER NOT NULL CHECK(is_ema200_buy IN (0, 1)),";
        sql += "is_ema200_sell INTEGER NOT NULL CHECK(is_ema200_sell IN (0, 1)),";
        sql += "created_at INTEGER NOT NULL,";
        sql += "created_at_text TEXT NOT NULL,";
        sql += "FOREIGN KEY(observation_id) REFERENCES ";
        sql += "zigzag_elliot_observations(id) ON DELETE CASCADE,";
        sql += "UNIQUE(observation_id, time_frame),";
        sql += "UNIQUE(observation_id, time_frame_order)";
        sql += ")";

        if (!this.executeSql(
                sql,
                "zigzag_elliot_observation_timeframes table"
            )) {
            return false;
        }

        if (!ZigZagElliotObservationJstMigration::execute(
                this.databaseHandle,
                "zigzag_elliot_observation_timeframes",
                "latest_point_time",
                "latest_point_jst_time",
                "latest_point_jst_time_text"
            )) {
            return false;
        }

        if (!ZigZagElliotObservationAddedPointMigration::execute(
                this.databaseHandle
            )) {
            return false;
        }

        sql = "CREATE UNIQUE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_observation_timeframes_anchor ";
        sql += "ON zigzag_elliot_observation_timeframes(observation_id) ";
        sql += "WHERE is_anchor_time_frame = 1";

        if (!this.executeSql(sql, "zigzag elliot observation anchor index")) {
            return false;
        }

        sql = "CREATE INDEX IF NOT EXISTS ";
        sql += "idx_zigzag_elliot_observation_timeframes_wave_lookup ";
        sql += "ON zigzag_elliot_observation_timeframes(";
        sql += "time_frame, latest_elliot_label, is_wave_motive,";
        sql += " is_wave_uptrend)";

        if (!this.executeSql(sql, "zigzag elliot observation wave index")) {
            return false;
        }

        this.logger.info(
            __FUNCTION__,
            "zigzag_elliot_observation_timeframes table and indexes are ready."
        );

        return true;
    }

    /**
     * 時間足別観測を保存する。
     *
     * 保存成功時はIDをfromEntity.idへ設定する。
     *
     * @param fromEntity 保存対象エンティティ。
     * @return 保存に成功した場合true。
     */
    bool insert(ZigZagElliotObservationTimeFrameEntity &fromEntity) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        fromEntity.id = 0;
        string sql = this.buildInsertSql();
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        if (!this.bindEntity(requestHandle, fromEntity)) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
            );

            return false;
        }

        bool isExecuted = this.executeRequest(
            requestHandle,
            __FUNCTION__,
            "insert observation timeframe"
        );
        DatabaseFinalize(requestHandle);

        if (!isExecuted) {
            return false;
        }

        return this.getLastInsertId(fromEntity.id);
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;

    /** ロガー。 */
    Logger logger;

    /**
     * 時間足別観測INSERT文を生成する。
     *
     * @return パラメーター化したINSERT文。
     */
    string buildInsertSql() {
        string sql = "INSERT INTO zigzag_elliot_observation_timeframes (";
        sql += "observation_id, time_frame, time_frame_text, time_frame_order,";
        sql += " is_anchor_time_frame, is_buy, buy_sell_label, wave_count,";
        sql += " latest_wave_index, is_wave_confirmed, is_wave_motive,";
        sql += " is_wave_uptrend, wave_trend_label, previous_last_elliot_label,";
        sql += " point_count, latest_elliot_index, latest_elliot_label,";
        sql += " latest_sub_elliot_index, latest_sub_elliot_label,";
        sql += " latest_point_time, latest_point_time_text,";
        sql += " latest_point_jst_time, latest_point_jst_time_text,";
        sql += " latest_point_rate, latest_point_is_added,";
        sql += " previous_open, previous_high, previous_low, previous_close,";
        sql += " current_open, current_high, current_low, current_close,";
        sql += " is_fibo_expansion_available, fe618_price, fe1000_price,";
        sql += " fe1272_price, fe1618_price, fe2000_price,";
        sql += " distance_to_fe2000_pips, oscillator_count, is_oscillator_buy,";
        sql += " stochastic_main_order, stochastic_main_order_text,";
        sql += " stochastic_main_direction_text, stochastic_short_count,";
        sql += " stochastic_short_main, stochastic_short_signal,";
        sql += " stochastic_middle_count, stochastic_middle_main,";
        sql += " stochastic_middle_signal, stochastic_long_count,";
        sql += " stochastic_long_main, stochastic_long_signal,";
        sql += " gmma_trend_count, gmma_cross_count, ema30, ema60,";
        sql += " ema30_ema60_diff_pips, atr14_pips, ema200_close1,";
        sql += " ema200_shift1, ema200_compare, ema200_slope_pips,";
        sql += " ema200_close_diff_pips, ema200_close_position,";
        sql += " ema200_slope_direction, ema200_up_count, ema200_down_count,";
        sql += " ema200_trend_count, is_ema200_buy, is_ema200_sell,";
        sql += " created_at, created_at_text";
        sql += ") VALUES (";

        for (int i = 1; i <= 74; i++) {
            if (i > 1) {
                sql += ", ";
            }

            sql += "?" + IntegerToString(i);
        }

        sql += ")";

        return sql;
    }

    /**
     * 時間足別観測INSERTパラメーターを設定する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromEntity 保存対象エンティティ。
     * @return 全パラメーターを設定できた場合true。
     */
    bool bindEntity(
        const int fromRequestHandle,
        ZigZagElliotObservationTimeFrameEntity &fromEntity
    ) {
        int index = 0;
        bool isBound = DatabaseBind(
            fromRequestHandle,
            index++,
            fromEntity.observationId
        );

        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.timeFrame);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.timeFrameText);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.timeFrameOrder);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isAnchorTimeFrame
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isBuy);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.buySellLabel);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.waveCount);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.latestWaveIndex);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isWaveConfirmed
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isWaveMotive);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isWaveUptrend);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.waveTrendLabel);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.previousLastElliotLabel
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.pointCount);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.latestElliotIndex
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.latestElliotLabel
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.latestSubElliotIndex
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.latestSubElliotLabel
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.latestPointTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.latestPointTimeText
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.latestPointJstTime
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.latestPointJstTimeText
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.latestPointRate
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.latestPointIsAdded
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.previousOpen);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.previousHigh);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.previousLow);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.previousClose);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.currentOpen);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.currentHigh);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.currentLow);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.currentClose);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isFiboExpansionAvailable
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.fe618Price);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.fe1000Price);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.fe1272Price);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.fe1618Price);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.fe2000Price);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.distanceToFe2000Pips
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.oscillatorCount);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.isOscillatorBuy
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.stochasticMainOrder
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.stochasticMainOrderText
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.stochasticMainDirectionText
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.stochasticShortCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.stochasticShortMain
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.stochasticShortSignal
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.stochasticMiddleCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.stochasticMiddleMain
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.stochasticMiddleSignal
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.stochasticLongCount
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.stochasticLongMain
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.stochasticLongSignal
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.gmmaTrendCount);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.gmmaCrossCount);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.ema30);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.ema60);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.ema30Ema60DiffPips
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.atr14Pips);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.ema200Close1);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.ema200Shift1);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.ema200Compare);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.ema200SlopePips);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.ema200CloseDiffPips
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.ema200ClosePosition
            );
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.ema200SlopeDirection
            );
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.ema200UpCount);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.ema200DownCount);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.ema200TrendCount);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isEma200Buy);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.isEma200Sell);
        }
        if (isBound) {
            isBound = DatabaseBind(fromRequestHandle, index++, fromEntity.createdAt);
        }
        if (isBound) {
            isBound = DatabaseBind(
                fromRequestHandle,
                index++,
                fromEntity.createdAtText
            );
        }

        return isBound && index == 74;
    }

    /**
     * 直前に追加したレコードIDを取得する。
     *
     * @param fromInsertId 取得したIDの格納先。
     * @return IDを取得できた場合true。
     */
    bool getLastInsertId(long &fromInsertId) {
        ResetLastError();
        int requestHandle = DatabasePrepare(
            this.databaseHandle,
            "SELECT last_insert_rowid()"
        );

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseRead failed. error=%d", readErrorCode)
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseColumnLong(requestHandle, 0, fromInsertId)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseColumnLong failed. error=%d", columnErrorCode)
            );

            return false;
        }

        DatabaseFinalize(requestHandle);

        if (fromInsertId <= 0) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("Invalid insert id. id=%I64d", fromInsertId)
            );

            return false;
        }

        return true;
    }

    /**
     * 結果行を返さない準備済みリクエストを実行する。
     *
     * @param fromRequestHandle リクエストハンドル。
     * @param fromMethodName 呼び出し元メソッド名。
     * @param fromOperationName 操作名。
     * @return 実行に成功した場合true。
     */
    bool executeRequest(
        const int fromRequestHandle,
        const string fromMethodName,
        const string fromOperationName
    ) {
        ResetLastError();
        bool isRead = DatabaseRead(fromRequestHandle);
        int errorCode = GetLastError();

        if (!isRead && errorCode != ERR_DATABASE_NO_MORE_DATA) {
            this.logger.error(
                fromMethodName,
                StringFormat(
                    "DatabaseRead failed. operation=%s error=%d",
                    fromOperationName,
                    errorCode
                )
            );

            return false;
        }

        return true;
    }

    /**
     * SQLを直接実行する。
     *
     * @param fromSql SQL文字列。
     * @param fromOperationName 操作名。
     * @return 実行に成功した場合true。
     */
    bool executeSql(
        const string fromSql,
        const string fromOperationName
    ) {
        ResetLastError();

        if (!DatabaseExecute(this.databaseHandle, fromSql)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseExecute failed. operation=%s error=%d",
                    fromOperationName,
                    GetLastError()
                )
            );

            return false;
        }

        return true;
    }

    /**
     * データベースハンドルが利用可能か確認する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @return 利用可能な場合true。
     */
    bool isDatabaseReady(const string fromMethodName) {
        if (this.databaseHandle != INVALID_HANDLE) {
            return true;
        }

        this.logger.error(fromMethodName, "databaseHandle is INVALID_HANDLE.");

        return false;
    }
};

#endif // MSTNG_DATABASE_DAO_ZIGZAG_ELLIOT_OBSERVATION_TF_DAO_MQH
