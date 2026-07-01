//+------------------------------------------------------------------+
//|                                         ExpertAdvisorBuySell.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Util\UtilAll.mqh>

//--- Entry judgment rank
enum ENUM_EXPERT_ADVISOR_ENTRY_RANK {
    EXPERT_ADVISOR_ENTRY_RANK_A = 0,
    EXPERT_ADVISOR_ENTRY_RANK_B1 = 1,  // Best B: H4 + H1 match M15, D1 mismatch
    EXPERT_ADVISOR_ENTRY_RANK_B2 = 2,  // Middle B: D1 + H1 match M15, H4 mismatch
    EXPERT_ADVISOR_ENTRY_RANK_B3 = 3,  // Weakest B: D1 + H4 match M15, H1 mismatch
    EXPERT_ADVISOR_ENTRY_RANK_C1 = 4,  // Best C: H1 only matches M15
    EXPERT_ADVISOR_ENTRY_RANK_C2 = 5,  // Middle C: H4 only matches M15
    EXPERT_ADVISOR_ENTRY_RANK_C3 = 6,  // Weakest C: D1 only matches M15
    EXPERT_ADVISOR_ENTRY_RANK_NON = 7
};

class ExpertAdvisorBuySell {
public:
    /** 判定対象の市場コンテキスト */
    MarketContext marketContext;

    ENUM_EXPERT_ADVISOR_ENTRY_RANK rank;
    string rankLabel;
    
    bool isBuy;

    /**
     * シンボルと時間足を指定して初期化する。
     *
     * @param fromSymbolName 判定対象シンボル
     * @param fromTimeFrame 判定対象時間足
     */
    ExpertAdvisorBuySell(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initialize(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 判定対象の市場コンテキスト
     */
    ExpertAdvisorBuySell(MarketContext &fromMarketContext) {
        this.initialize(fromMarketContext);
    }
    
    ~ExpertAdvisorBuySell() {
    }

    /**
     * 判定対象の市場コンテキストを設定する。
     *
     * 旧市場の売買方向と判定ランクを初期状態へ戻す。
     *
     * @param fromMarketContext 判定対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
        this.logger.setMarketContext(this.marketContext);
        this.rank = EXPERT_ADVISOR_ENTRY_RANK_NON;
        this.rankLabel = ExpertAdvisorBuySell::convertEntryRankToString(this.rank);
        this.isBuy = false;
    }
    
    void setRank(ElliotAll *fromElliotAll) {
        if (fromElliotAll == NULL) {
            this.rank = EXPERT_ADVISOR_ENTRY_RANK_NON;
            this.rankLabel = ExpertAdvisorBuySell::convertEntryRankToString(this.rank);
            return;
        }
    
        bool isBuyD1  = fromElliotAll.getElliot(PERIOD_D1).isBuy;
        bool isBuyH4  = fromElliotAll.getElliot(PERIOD_H4).isBuy;
        bool isBuyH1  = fromElliotAll.getElliot(PERIOD_H1).isBuy;
        bool isBuyM15 = fromElliotAll.getElliot(PERIOD_M15).isBuy;
        
        this.isBuy = isBuyM15;
    
        this.rank = this.getRank(isBuyD1, isBuyH4, isBuyH1, isBuyM15);
        this.rankLabel = ExpertAdvisorBuySell::convertEntryRankToString(this.rank);
    }
    
    ENUM_EXPERT_ADVISOR_ENTRY_RANK getRank(bool isBuyD1, bool isBuyH4, bool isBuyH1, bool isBuyM15) {
        bool matchD1 = (isBuyD1 == isBuyM15);
        bool matchH4 = (isBuyH4 == isBuyM15);
        bool matchH1 = (isBuyH1 == isBuyM15);

        int matchCount = 0;

        if (matchD1) {
            matchCount++;
        }

        if (matchH4) {
            matchCount++;
        }

        if (matchH1) {
            matchCount++;
        }

        if (matchCount == 3) {
            return EXPERT_ADVISOR_ENTRY_RANK_A;
        }

        // Rank B sequence: B1 is best, B3 is weakest.
        if (matchCount == 2) {
            if (matchH4 && matchH1) {
                return EXPERT_ADVISOR_ENTRY_RANK_B1;
            }

            if (matchD1 && matchH1) {
                return EXPERT_ADVISOR_ENTRY_RANK_B2;
            }

            if (matchD1 && matchH4) {
                return EXPERT_ADVISOR_ENTRY_RANK_B3;
            }
        }

        // Rank C sequence: C1 is best, C3 is weakest.
        if (matchCount == 1) {
            if (matchH1) {
                return EXPERT_ADVISOR_ENTRY_RANK_C1;
            }

            if (matchH4) {
                return EXPERT_ADVISOR_ENTRY_RANK_C2;
            }

            if (matchD1) {
                return EXPERT_ADVISOR_ENTRY_RANK_C3;
            }
        }

        return EXPERT_ADVISOR_ENTRY_RANK_NON;
    }

    static string convertEntryRankToString(ENUM_EXPERT_ADVISOR_ENTRY_RANK fromRank) {
        switch(fromRank) {
            case EXPERT_ADVISOR_ENTRY_RANK_A:
                return "A";
            case EXPERT_ADVISOR_ENTRY_RANK_B1:
                return "B1";
            case EXPERT_ADVISOR_ENTRY_RANK_B2:
                return "B2";
            case EXPERT_ADVISOR_ENTRY_RANK_B3:
                return "B3";
            case EXPERT_ADVISOR_ENTRY_RANK_C1:
                return "C1";
            case EXPERT_ADVISOR_ENTRY_RANK_C2:
                return "C2";
            case EXPERT_ADVISOR_ENTRY_RANK_C3:
                return "C3";
            case EXPERT_ADVISOR_ENTRY_RANK_NON:
                return "NON";
            default:
                return "UNKNOWN";
        }
    }

    static string getEntryRankString(ENUM_EXPERT_ADVISOR_ENTRY_RANK fromRank) {
        return ExpertAdvisorBuySell::convertEntryRankToString(fromRank);
    }

private:
    Logger logger;

    /**
     * 市場コンテキストと初期ランクを設定する。
     *
     * @param fromMarketContext 判定対象の市場コンテキスト
     */
    void initialize(MarketContext &fromMarketContext) {
        this.logger.setLevel(LOG_INFO);
        this.setMarketContext(fromMarketContext);
    }

};
