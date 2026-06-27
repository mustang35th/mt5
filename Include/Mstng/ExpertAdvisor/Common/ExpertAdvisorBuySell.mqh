//+------------------------------------------------------------------+
//|                                         ExpertAdvisorBuySell.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
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
    ENUM_EXPERT_ADVISOR_ENTRY_RANK rank;
    string rankLabel;
    
    bool isBuy;
    
    ExpertAdvisorBuySell(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        this.logger.setLevel(LOG_INFO);
        this.logger.setSymbolNameAndTimeFrame(fromSymbolName, fromTimeFrame);
        
        this.symbolName = fromSymbolName;
        this.timeFrame = fromTimeFrame;
        this.timeFrameLabel = TimeUtil::convertTimeFrameToString(this.timeFrame);
        
        this.rank = EXPERT_ADVISOR_ENTRY_RANK_NON;
        this.rankLabel = ExpertAdvisorBuySell::convertEntryRankToString(this.rank);
    }
    
    ~ExpertAdvisorBuySell() {
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
    
    string symbolName;
    ENUM_TIMEFRAMES timeFrame;
    string timeFrameLabel;

};