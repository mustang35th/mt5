#ifndef MSTNG_DATABASE_ZIGZAG_ELLIOT_OBSERVATION_WRITER_LOCK_MQH
#define MSTNG_DATABASE_ZIGZAG_ELLIOT_OBSERVATION_WRITER_LOCK_MQH

/**
 * 観測DB、実行モード、基準時間足ごとのWriterを排他的に保持するクラス。
 * DBと同じ保存先に共有なしで開いたハンドルを保持し、ファイルの存在は判定しない。
 */
class ZigZagElliotObservationWriterLock {
public:
    /**
     * 未取得状態で初期化する。
     */
    ZigZagElliotObservationWriterLock() {
        this.handle = INVALID_HANDLE;
    }

    /**
     * 終了時にハンドルを解放する。残った空ファイルは削除しない。
     */
    ~ZigZagElliotObservationWriterLock() {
        this.release();
    }

    /**
     * 指定保存先のWriter用排他ハンドルを取得する。
     *
     * @param fromDatabaseFileName 観測DBの相対ファイル名。
     * @param fromUseCommonFolder DBがCommonフォルダを使用する場合true。
     * @param fromSourceMode LIVEまたはTESTER。
     * @param fromAnchorTimeFrameText H1またはM5などの基準時間足名。
     * @return 取得済みまたは今回取得に成功した場合true。
     */
    bool acquire(
        const string fromDatabaseFileName,
        const bool fromUseCommonFolder,
        const string fromSourceMode,
        const string fromAnchorTimeFrameText
    ) {
        if (this.isHeld()) {
            return true;
        }

        if (fromDatabaseFileName == "") {
            return false;
        }

        string fileName = fromDatabaseFileName + "." + fromSourceMode
            + "." + fromAnchorTimeFrameText + ".writer.lock";
        int flags = FILE_BIN | FILE_READ | FILE_WRITE;
        if (fromUseCommonFolder) {
            flags |= FILE_COMMON;
        }

        this.handle = FileOpen(fileName, flags);

        return this.isHeld();
    }

    /**
     * Writer用排他ハンドルを保持しているか返す。
     *
     * @return 取得済みの場合true。
     */
    bool isHeld() const {
        return this.handle != INVALID_HANDLE;
    }

    /**
     * 排他ハンドルだけを解放する。DBやsidecarファイルは削除しない。
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
