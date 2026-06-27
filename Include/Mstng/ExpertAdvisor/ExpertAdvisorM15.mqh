//+------------------------------------------------------------------+
//|                                             ExpertAdvisorM15.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\ExpertAdvisor\AbstractExpertAdvisor.mqh>

class ExpertAdvisorM15 : public AbstractExpertAdvisor {
public:
    
    ExpertAdvisorM15() {
        this.logger.setLevel(LOG_INFO);
    }
    
    ~ExpertAdvisorM15() {
    }
        
protected:
    

};