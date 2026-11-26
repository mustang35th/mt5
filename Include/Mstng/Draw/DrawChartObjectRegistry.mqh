#ifndef MSTNG_DRAW_CHART_OBJECT_REGISTRY_MQH
#define MSTNG_DRAW_CHART_OBJECT_REGISTRY_MQH

/**
 * 一枚の描画が所有する名前を保持し、既存要素の再利用と不要要素の回収を行う。
 * 別世代を非表示で組み立てる場合は、完成後に背景から文字の順で公開する。
 */
class DrawChartObjectRegistry {
public:
    /**
     * オブジェクトを所有しない状態で初期化する。
     */
    DrawChartObjectRegistry() {
        this.chartId = 0;
        this.hidden = false;
    }

    /**
     * 今回使用する名前の記録を開始する。
     */
    void begin(const long fromChartId, const bool fromHidden = false) {
        this.chartId = fromChartId;
        this.hidden = fromHidden;
        for (int i = 0; i < ArraySize(this.used); i++) {
            this.used[i] = false;
        }
    }

    /**
     * 名前を使用中として記録し、存在しない要素だけを作成する。
     */
    bool ensure(const string fromName, const ENUM_OBJECT fromType) {
        int index = -1;
        int count = ArraySize(this.names);
        for (int i = 0; i < count; i++) {
            if (this.names[i] == fromName) {
                index = i;
                break;
            }
        }

        if (index < 0) {
            if (ArrayResize(this.names, count + 1) != count + 1) {
                return false;
            }

            if (ArrayResize(this.used, count + 1) != count + 1) {
                ArrayResize(this.names, count);

                return false;
            }

            index = count;
            this.names[index] = fromName;
        }

        this.used[index] = true;
        if (ObjectFind(this.chartId, fromName) >= 0) {
            return true;
        }

        if (!ObjectCreate(this.chartId, fromName, fromType, 0, 0, 0)) {
            return false;
        }

        if (this.hidden) {
            return ObjectSetInteger(this.chartId, fromName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        }

        return true;
    }

    /**
     * 描画されなかった要素だけを削除し、使用中の名前を残す。
     */
    bool finish() {
        bool success = true;
        int count = 0;
        for (int i = 0; i < ArraySize(this.names); i++) {
            bool keep = this.used[i];
            if (!keep && ObjectFind(this.chartId, this.names[i]) >= 0
                    && !ObjectDelete(this.chartId, this.names[i])) {
                success = false;
                keep = true;
            }
            if (keep) {
                this.names[count] = this.names[i];
                this.used[count] = this.used[i];
                count++;
            }
        }

        ArrayResize(this.names, count);
        ArrayResize(this.used, count);

        return success;
    }

    /**
     * 非表示の新世代を作成順で公開し、表示順が変わっても背景を文字より奥に保つ。
     * 公開中は同期取得を挟まず、背景から文字までの要求をまとめて送る。
     */
    bool show() {
        int count = ArraySize(this.names);
        if (count > 0 && ObjectFind(this.chartId, this.names[count - 1]) < 0) {
            return false;
        }

        bool success = true;
        for (int i = 0; i < count; i++) {
            bool shown = ObjectSetInteger(this.chartId, this.names[i], OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
            success = shown && success;
        }

        this.hidden = false;

        return success;
    }

    /**
     * 追跡している要素だけを解放する。
     */
    void clear() {
        for (int i = 0; i < ArraySize(this.names); i++) {
            ObjectDelete(this.chartId, this.names[i]);
        }

        ArrayFree(this.names);
        ArrayFree(this.used);
    }

    /**
     * 所有する名前がない場合trueを返す。
     */
    bool isEmpty() { return ArraySize(this.names) == 0; }

private:
    /** 描画先チャート。 */
    long chartId;

    /** 今回の世代を非表示で組み立てる場合true。 */
    bool hidden;

    /** 作成順に保持する所有オブジェクト名。 */
    string names[];

    /** 今回の描画で使われた名前の場合true。 */
    bool used[];
};

#endif // MSTNG_DRAW_CHART_OBJECT_REGISTRY_MQH
