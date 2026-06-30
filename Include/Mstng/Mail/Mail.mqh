//+------------------------------------------------------------------+
//|                                                         Mail.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\ExpertAdvisor\AbstractExpertAdvisor.mqh>

class Mail {
public:
    static void sendMail(ElliotAll *fromElliotAll, bool isSendMail = false) {
        string title = getTitle(fromElliotAll);
        string body = getBody(fromElliotAll);
        
        Print(__FUNCTION__, " isSendMail = ", isSendMail);
        Print(__FUNCTION__, " title = ", title);
        Print(__FUNCTION__, " body = ", body);
        
        if (isSendMail) {
            if (fromElliotAll.isTimer) {
                SendMail(title, body);
            }
        }
    }

private:
    static string getTitle(ElliotAll *fromElliotAll) {
        string symbolName = fromElliotAll.marketContext.symbolName;
        string buySellLabel = fromElliotAll.elliotCurrent.buySellLabel;
        string mailTitile = fromElliotAll.mailTitile;
        
        return StringFormat("%s:%s:%s", symbolName, buySellLabel, mailTitile);
    }
    
    static string getBody(ElliotAll *fromElliotAll) {
        string text = "";
        
        text += StringFormat("%s\n", TimeUtil::formatYyyymmddhhmiss(fromElliotAll.tradeTimeInfo.jstTime));
        
        // レート
        TodayRate todayRate = fromElliotAll.todayRate;
        
        text += StringFormat("Bid:%s Ask:%s spread:%spips\n", todayRate.bidLabel, todayRate.askLabel, todayRate.spreadLabel);
        text += StringFormat("H:%s L:%s\n", todayRate.highLabel, todayRate.lowLabel);
        text += StringFormat("D:%spips", todayRate.diffLabel);
        
        if (todayRate.diffJpy > 0) {
            text += StringFormat(" D Jpy:%spips", todayRate.diffJpyLabel);
        }
        
        text += "\n\n";
        
        text += StringFormat("GMT:%s\n\n", TimeUtil::formatYyyymmddhhmiss(fromElliotAll.tradeTimeInfo.serverTime));
        
        // ロスカット
        text += StringFormat("%s\n", fromElliotAll.lossCut.getText());
	    
	    // 市場分析
	    //text += StringFormat("%s\n\n", fromElliotAll.marketActivityAnalyzer.toString());
	    
	    // エリオット
	    text += "エリオット\n";
	    text += StringFormat("%s\n", fromElliotAll.getText());
	    
        return text;
    }

};

/*
ZigZagElliot NZDUSD.oj1m,M15: MailAbstractExpertAdvisor::sendMail isSendMail=true
ZigZagElliot NZDUSD.oj1m,M15: MailAbstractExpertAdvisor::sendMail mailTitle=NZDUSD:BUY[▲3-<IF>5-3-<F>3]:
ZigZagElliot NZDUSD.oj1m,M15: MailAbstractExpertAdvisor::sendMail mailBody=2026/02/10 11:15:00
Bid:0.60499 Ask:0.60513 spread:1.4pips
H:0.60555 L:0.60305 D:25pips

LC M15
diff:20.8pips
0->0.60305
5->0.60255
10->0.60205
15->0.60155

エリオット最新
MN1:★▼4[F71.1%]<635.2p>0.61198
BUY/ S/+3/ M/+3/+9/ H/+1/ G/0/0/
 -> +3

W1:未▲C[FE81.4%]<517.0p>0.60920
BUY/ S/+4/ M/+5/+10/ H/+4/ G/0/0/
 -> +3

D1:▲3[FE137.4%]<381.5p>0.60920
BUY/ S/+2/ M/+2/-4/ H/+16/ G/0/0/
 -> +3

H4:IMP:FRA:未▲5[FE35.9%]<131.8p>0.60594
BUY/ S/-1/ M/+13/+10/ H/+10/ G/0/0/
 -> +2

H1:▲3[FE59.5%]<63.0p>0.60594
BUY/ S/+1/ M/-6/-3/ H/+15/ G/+16/+28/
 -> +2

M15:FRA:★▲3[FE39.7%]<25.0p>0.60555
BUY/ S/+7/ M/+3/+1/ H/+1/ G/+3/+171/
 -> +3

*/
