#ifndef MSTNGH1EA_RUNTIME_INSTANCELOCK_MQH
#define MSTNGH1EA_RUNTIME_INSTANCELOCK_MQH

#include <MstngH1Ea\Runtime\H1EaTextUtil.mqh>

/**
 * DB障害中も二重管理を防ぐCommonファイルの排他ハンドル。
 * ファイルの存在ではなく共有なしで開いたOSハンドルを正本とする。
 */
class H1EaInstanceLock {
public:
    /**
     * 未取得状態で初期化する。
     */
    H1EaInstanceLock() {
        this.handle = INVALID_HANDLE;
    }

    /**
     * 終了時にハンドルを解放する。残った空ファイルは削除しない。
     */
    ~H1EaInstanceLock() {
        this.release();
    }

    /**
     * 同一口座・シンボル・Magicの管理権を排他的に取得する。
     */
    bool acquire(const string fromScope) {
        if (this.isHeld()) {
            return false;
        }
        string scopeHash = H1EaTextUtil::hash(fromScope);
        if (StringLen(scopeHash) != 64) {
            return false;
        }
        FolderCreate("MstngH1Ea", FILE_COMMON);
        FolderCreate("MstngH1Ea\\Locks", FILE_COMMON);
        this.handle = FileOpen("MstngH1Ea\\Locks\\" + scopeHash + ".lock",
            FILE_BIN | FILE_READ | FILE_WRITE | FILE_COMMON);
        return this.isHeld();
    }

    /**
     * 排他ハンドルを保持しているか返す。
     */
    bool isHeld() const {
        return this.handle != INVALID_HANDLE;
    }

    /**
     * 排他ハンドルだけを解放する。
     */
    void release() {
        if (this.isHeld()) {
            FileClose(this.handle);
            this.handle = INVALID_HANDLE;
        }
    }

private:
    /** 稼働中保持する共有なしファイルハンドル。 */
    int handle;
};

#endif
