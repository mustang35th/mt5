//+------------------------------------------------------------------+
//|                                         DrawPropertiesElliot.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Object.mqh>

class DrawPropertiesElliot : public CObject {
public:
    bool isVisible;
    int width;
    
    DrawPropertiesElliot(bool fromIsVisible, int fromWidth) {
        this.isVisible = fromIsVisible;
        this.width = fromWidth;
    }

    ~DrawPropertiesElliot() {
    }
};