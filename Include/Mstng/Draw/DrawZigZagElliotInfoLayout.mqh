//+------------------------------------------------------------------+
//|                                  DrawZigZagElliotInfoLayout.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_DRAW_ZIGZAG_ELLIOT_INFO_LAYOUT_MQH
#define MSTNG_DRAW_ZIGZAG_ELLIOT_INFO_LAYOUT_MQH

/**
 * ZigZagElliotの右側情報欄で共用する幅・余白・縦位置を定義する。
 * 右端基準の座標と各ラベルのアンカーを組み合わせ、画面幅に追従する。
 */
class DrawZigZagElliotInfoLayout {
public:
    /**
     * 情報欄の共通幅を返す。
     */
    static int getWidth() { return 280; }

    /**
     * チャート右端に確保する最小余白を返す。
     */
    static int getMinimumRightDistance() { return 10; }

    /**
     * 項目名の右に揃える日時・方式の開始位置を返す。
     */
    static int getTimeValueLeftOffset() { return 40; }

    /**
     * JST・サーバー・M5日時に共用する文字サイズを返す。
     */
    static int getTimeFontSize() { return 14; }

    /**
     * H・L・A・Bの価格を右揃えする位置を返す。
     */
    static int getPriceValueRightOffset() { return getWidth() / 2 - 8; }

    /**
     * D・S・円換算値幅の項目名を置く右列の開始位置を返す。
     */
    static int getSecondaryTitleLeftOffset() { return getWidth() / 2 + 8; }

    /**
     * D・Sの項目名のすぐ右に揃える数値の開始位置を返す。
     */
    static int getSecondaryValueLeftOffset() { return getSecondaryTitleLeftOffset() + 32; }

    /**
     * 情報欄内の左位置を、チャート右端からの距離へ変換する。
     *
     * @param fromRightDistance 情報欄とチャート右端の間の余白
     * @param fromLeftOffset 情報欄の左端からの位置
     * @return 右上・右下基準のオブジェクトへ設定するX距離
     */
    static int getXDistance(int fromRightDistance, int fromLeftOffset = 0) {
        int rightDistance = fromRightDistance;
        if (rightDistance < getMinimumRightDistance()) {
            rightDistance = getMinimumRightDistance();
        }

        return rightDistance + getWidth() - fromLeftOffset;
    }

    /**
     * 時計の下に置く処理時間欄の上端を返す。
     */
    static int getProcessingTop() { return 248; }

    /**
     * 処理時間欄の2行を含む下端を返す。
     */
    static int getProcessingBottom() { return getProcessingTop() + 32; }

    /**
     * 処理時間欄の下へ8px空けた通貨強弱欄の上端を返す。
     */
    static int getStrengthTop() { return getProcessingBottom() + 8; }

    /**
     * 横一列に配置する各操作ボタンの幅を返す。
     */
    static int getButtonWidth() { return 88; }

    /**
     * 操作ボタン間の余白を返す。
     */
    static int getButtonGap() { return 8; }
};

#endif
