"""Run the production history-readiness branches against a simulated series API.

Only MQL syntax and external MT5 series/time/log APIs are adapted to C#.
This does not execute MT5, indicator buffers, strategy decisions, or trades.
Controller lifecycle/order checks are explicitly source contracts.
"""

from pathlib import Path
import re
import sys
import unittest


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/Mstng/Database"))
from test_m5_observation_history_reader import block_end, code_only, method, run_csharp


DIRECTORY = ROOT / "Include/Mstng/Indicator/ZigZagElliot"
READINESS = DIRECTORY / "ElliotHistoryReadiness.mqh"
CONTROLLER = DIRECTORY / "ZigZagElliotController.mqh"


def syntax(source):
    """Adapt scalar/array references without replacing any readiness branches."""
    source = re.sub(r"\bconst\s+(\w+)\s*&\s*(\w+)\[\]", r"\1[] \2", source)
    source = re.sub(r"\bconst\s+", "", source)
    source = re.sub(r"\bdatetime\b", "long", source)
    source = re.sub(r"\bENUM_TIMEFRAMES\b", "int", source)
    source = re.sub(r"\b(\w+)::(\w+)(?=\s*\()", r"\1.\2", source).replace("NULL", "null")
    source = re.sub(r"\b(int|bool|long)\s*&\s*(\w+)\[\]", r"ref \1[] \2", source)
    source = re.sub(r"\b(\w+)\s*&\s*(\w+)", r"\1 \2", source)
    source = re.sub(r"\b(int|bool|long)\s+(\w+)\[\]\s*=\s*\{", r"\1[] \2 = new \1[] {", source)
    source = re.sub(r"\b(int|bool|long)\s+(\w+)\[\]\s*;", r"\1[] \2 = new \1[0];", source)
    source = re.sub(r"\b(int|bool|long)\s+(\w+)\[(\d+)\]\s*;", r"\1[] \2 = new \1[\3];", source)
    source = re.sub(r"ArrayResize\(([^,]+),", r"ArrayResize(ref \1,", source)
    source = re.sub(r"ArrayCopy\(([^,]+),", r"ArrayCopy(ref \1,", source)
    source = re.sub(r"(ElliotTimeFrameRange\.build\([^;]+?,\s*)(this\.\w+)(\s*\))", r"\1ref \2\3", source)
    source = re.sub(r"\b(MarketContext|Logger)\s+(\w+)\s*;", r"\1 \2 = new \1();", source)
    source = source.replace("this.marketContext = fromMarketContext;",
                            "this.marketContext = new MarketContext(fromMarketContext.symbolName,fromMarketContext.timeFrame);")
    return source


def class_fixture(source, name):
    opening = re.search(r"\bclass " + name + r"\s*\{", source).end() - 1
    body = source[opening + 1:block_end(code_only(source), opening)]
    body = re.sub(r"\b(?:public|protected|private)\s*:", "", body)
    body = re.sub(r"\benum\s+\w+\s*\{([^}]+)\};", lambda match: "\n".join(
        "    const int " + assignment.strip() + ";" for assignment in
        re.sub(r"/\*.*?\*/", "", match[1], flags=re.S).split(",") if assignment.strip()), body)
    body = syntax(body)
    body = re.sub(r"^(\s{4})(?=(?:static\s+)?(?:bool|void|int|long|string|" + name + r")\b[^\n;=]*\()",
                  r"\1public ", body, flags=re.M)
    return "public class " + name + " : MqlApi {\n" + body + "\n}\n"


API = r'''
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
public class MqlApi {
    public const int PERIOD_CURRENT=0,PERIOD_M1=1,PERIOD_M5=5,PERIOD_M15=15,
        PERIOD_H1=16385,PERIOD_H4=16388,PERIOD_D1=16408,PERIOD_W1=32769,PERIOD_MN1=49153;
    public const int TIME_DATE=1,TIME_MINUTES=2,LOG_INFO=1;
    public const string __FUNCTION__="fixture";
    public static int[] Periods={PERIOD_MN1,PERIOD_W1,PERIOD_D1,PERIOD_H4,PERIOD_H1,PERIOD_M15,PERIOD_M5,PERIOD_M1};
    public static Dictionary<int,bool> Synchronized=new Dictionary<int,bool>();
    public static Dictionary<int,int> BarCounts=new Dictionary<int,int>();
    public static List<string> Calls=new List<string>();
    public static List<string> Logs=new List<string>();
    public static List<string> LogScopes=new List<string>();
    public static long CurrentTime=1795500000,BarTime=1795500000;
    public static void Reset() {
        Calls.Clear();Logs.Clear();LogScopes.Clear();Synchronized.Clear();BarCounts.Clear();
        foreach(int frame in Periods) { Synchronized[frame]=true;BarCounts[frame]=1000; }
        CurrentTime=1795500000;BarTime=1795500000;
    }
    public static int ArraySize<T>(T[] array) { return array.Length; }
    public static int ArrayResize<T>(ref T[] array,int count) { Array.Resize(ref array,count);return count; }
    public static void ArrayInitialize<T>(T[] array,T value) { for(int i=0;i<array.Length;i++) array[i]=value; }
    public static int ArrayCopy<T>(ref T[] target,T[] source) { target=(T[])source.Clone();return source.Length; }
    public static int Bars(string symbol,int frame) { Calls.Add("bars:"+symbol+":"+frame);return BarCounts[frame]; }
    public static long iTime(string symbol,int frame,int shift) { Calls.Add("time:"+symbol+":"+frame);return BarTime; }
    public static long TimeCurrent() { return CurrentTime; }
    public static int PeriodSeconds(int frame) {
        if(frame<16385) return frame*60;
        if(frame==PERIOD_H1) return 3600;
        if(frame==PERIOD_H4) return 14400;
        if(frame==PERIOD_D1) return 86400;
        if(frame==PERIOD_W1) return 604800;
        return 2592000;
    }
    public static string EnumToString(int frame) { return "PERIOD_"+TimeUtil.convertTimeFrameToString(frame); }
    public static string TimeToString(long value,int flags) { return new DateTime(1970,1,1).AddSeconds(value).ToString("yyyy.MM.dd HH:mm",CultureInfo.InvariantCulture); }
    public static string StringFormat(string format,params object[] values) {
        int offset=0;
        return Regex.Replace(format,@"%%|%[ds]",match=>match.Value=="%%" ? "%" : Convert.ToString(values[offset++],CultureInfo.InvariantCulture));
    }
}
public class MarketContext {
    public string symbolName="USDJPY";public int timeFrame=MqlApi.PERIOD_M1;
    public MarketContext() {}
    public MarketContext(string symbol,int frame) { symbolName=symbol;timeFrame=frame; }
}
public class Logger {
    public void info(string caller,string text) { MqlApi.Logs.Add(text);MqlApi.LogScopes.Add(caller); }
    public void setLevel(int level) {}
    public void setMarketContext(MarketContext context) {}
}
public class WarmUpSeriesUtil : MqlApi {
    public static bool isSeriesSynchronized(string symbol,int frame) {
        Calls.Add("sync:"+symbol+":"+frame);return Synchronized[frame];
    }
    public static void warmUp(MarketContext context,int[] frames,int count) {
        Calls.Add("request:"+context.symbolName+":"+String.Join(",",frames)+":"+count);
    }
}
public class TimeUtil : MqlApi {
    public static string convertTimeFrameToString(int frame) {
        string[] names={"MN1","W1","D1","H4","H1","M15","M5","M1"};
        int position=Array.IndexOf(Periods,frame);return position<0 ? "CURRENT" : names[position];
    }
}
'''


def production_fixture():
    profile = (ROOT / "Include/Mstng/Elliot/ZigZagElliotAnalysisProfile.mqh").read_text(encoding="utf-8-sig")
    profile_body = syntax(method(profile, "getAnalysisStartTimeFrame"))
    source = API + "public class ZigZagElliotAnalysisProfile : MqlApi { public static int getAnalysisStartTimeFrame() {" + profile_body + "} }\n"
    source += class_fixture((ROOT / "Include/Mstng/Elliot/ElliotTimeFrameRange.mqh").read_text(encoding="utf-8-sig"), "ElliotTimeFrameRange")
    source += class_fixture(READINESS.read_text(encoding="utf-8-sig"), "ElliotHistoryReadiness")
    return source


SETUP = r'''
public class ReadinessFixture : MqlApi {
    static int checks;
    static Logger logger=new Logger();
    static void Check(bool value,string text) { checks++;if(!value) throw new Exception(text); }
    static int Requests() { return Calls.Count(item=>item.StartsWith("request:")); }
    static int Reads() { return Calls.Count(item=>item.StartsWith("bars:")); }
    static ElliotHistoryReadiness Create(bool live=false,int frame=PERIOD_M1) {
        ElliotHistoryReadiness readiness=new ElliotHistoryReadiness();
        Check(readiness.initialize(new MarketContext("USDJPY",frame),live),"initialize supported frame");
        return readiness;
    }
'''


class ElliotHistoryReadinessTests(unittest.TestCase):
    def execute(self, body):
        source = production_fixture() + SETUP + "public static string Run() { Reset();\n" + body
        source += '\nreturn "PASS "+checks+" readiness assertions"; } }\n'
        self.assertRegex(run_csharp(source, "[ReadinessFixture]::Run()\n"), r"PASS \d+ readiness assertions")

    def test_initial_request_range_and_live_sync_without_tester_bar_gate(self):
        self.execute(r'''
        ElliotHistoryReadiness readiness=Create(true,PERIOD_M15);
        Check(!readiness.isWarmingUp(),"live mode never waits for tester bar progress");
        Check(Calls.Count==0,"initialization only prepares state and preserves request timing");
        readiness.requestHistory();
        Check(Requests()==1 && Calls[0]=="request:USDJPY:49153,32769,16408,16388,16385,15:500","initial request covers exactly MN1 through M15 with 500 bars");
        Calls.Clear();foreach(int frame in Periods) BarCounts[frame]=0;
        Check(readiness.isReady(logger),"live readiness relies on synchronization and does not require tester bar thresholds");
        Check(Reads()==0 && !Calls.Any(item=>item.StartsWith("time:")),"live checks omit tester bar progress and bar-time reads");
        Synchronized[PERIOD_H4]=false;Synchronized[PERIOD_M15]=false;Calls.Clear();Logs.Clear();
        Check(!readiness.isReady(logger) && Requests()==2 && Logs.Count==1,"live requests every missing series but logs only first missing frame");
        Check(LogScopes.Last()=="ZigZagElliotController::isAnalysisDataReady","readiness log retains original function scope");
        Check(!readiness.isReady(logger) && Requests()==4 && Logs.Count==2,"live requests are retried even within same chart bar");
        ''')

    def test_tester_bar_thresholds_progress_and_completed_state(self):
        self.execute(r'''
        ElliotHistoryReadiness readiness=Create();
        Check(readiness.isWarmingUp(),"new tester starts warming up");
        foreach(int frame in Periods) BarCounts[frame]=206;
        BarCounts[PERIOD_MN1]=60;
        Check(!readiness.isReady(logger),"60 monthly bars are not sufficient");
        Check(Logs.Count==1 && Logs[0].Contains("progress=98%") && Logs[0].Contains("bottleneck=MN1") && Logs[0].Contains("bars=60/61"),"monthly threshold is 61 and contributes to minimum progress");
        Check(!readiness.isReady(logger) && Logs.Count==1,"unchanged progress is silent");
        BarCounts[PERIOD_MN1]=61;BarCounts[PERIOD_M1]=205;
        Check(!readiness.isReady(logger) && Logs.Last().Contains("bottleneck=M1") && Logs.Last().Contains("bars=205/206"),"other frames need 206 bars");
        BarCounts[PERIOD_M1]=206;
        Check(readiness.isReady(logger) && !readiness.isWarmingUp(),"all exact thresholds complete warmup");
        Check(Logs.Count==3 && Logs.Last().Contains("completed.") && Logs.Last().Contains("progress=100%"),"completion logs once with all available bars");
        Check(LogScopes.All(scope=>scope=="ZigZagElliotController::isTesterAnalysisHistoryReady"),"progress log retains original function scope");
        Check(readiness.isReady(logger) && Logs.Count==3,"repeated ready checks do not repeat completion log");
        Synchronized[PERIOD_M5]=false;Calls.Clear();Logs.Clear();
        Check(!readiness.isReady(logger) && !readiness.isReady(logger) && Requests()==2,"completed tester still retries missing history each execution");
        Check(!Calls.Any(item=>item.StartsWith("time:")),"completed warmup no longer uses per-bar request deduplication");
        Synchronized[PERIOD_M5]=true;BarCounts[PERIOD_W1]=100;
        Check(!readiness.isReady(logger) && readiness.isWarmingUp(),"a later bar-count regression re-enters warmup");
        ''')

    def test_tester_deduplicates_per_series_and_rearms_after_sync(self):
        self.execute(r'''
        ElliotHistoryReadiness readiness=Create();
        Synchronized[PERIOD_MN1]=false;Synchronized[PERIOD_M5]=false;
        Check(!readiness.isReady(logger) && Requests()==2 && Logs.Count==2,"first tester request handles every missing frame");
        Check(Reads()==0,"bar-count gate waits for all series to synchronize");
        Check(!readiness.isReady(logger) && Requests()==2 && Logs.Count==2,"same bar suppresses duplicate requests and associated logs");
        Synchronized[PERIOD_MN1]=true;
        Check(!readiness.isReady(logger) && Requests()==2,"synchronized series rearms without requesting other missing series twice");
        Synchronized[PERIOD_MN1]=false;
        Check(!readiness.isReady(logger) && Requests()==3,"loss of synchronization rearms that series within the same bar");
        BarTime+=60;
        Check(!readiness.isReady(logger) && Requests()==5,"new displayed bar allows both missing series to retry");
        ''')

    def test_missing_bar_time_uses_chart_period_and_zero_waits(self):
        self.execute(r'''
        ElliotHistoryReadiness readiness=Create(false,PERIOD_M15);
        Synchronized[PERIOD_M15]=false;BarTime=0;CurrentTime=1801;
        Check(!readiness.isReady(logger) && Requests()==1,"fallback time starts request");
        CurrentTime=2699;
        Check(!readiness.isReady(logger) && Requests()==1,"fallback rounds simulated time to the displayed 15-minute period");
        CurrentTime=2700;
        Check(!readiness.isReady(logger) && Requests()==2,"next displayed period rearms request");
        readiness=Create(false,PERIOD_M15);Calls.Clear();Logs.Clear();CurrentTime=0;
        Check(!readiness.isReady(logger) && !readiness.isReady(logger) && Requests()==1,"unknown bar and simulated time permit only first request");
        BarTime=1234;CurrentTime=1800;
        Check(!readiness.isReady(logger) && Requests()==2,"real bar time takes priority over rounded current time");
        CurrentTime=9999;
        Check(!readiness.isReady(logger) && Requests()==2,"stable real bar time keeps deduplication even if current time changes");
        ''')

    def test_progress_clamps_invalid_counts_and_compares_exact_ratios(self):
        self.execute(r'''
        ElliotHistoryReadiness readiness=Create();
        BarCounts[PERIOD_MN1]=-1;
        Check(!readiness.isReady(logger) && Logs.Last().Contains("progress=0%") && Logs.Last().Contains("bars=-1/61"),"negative counts clamp progress but retain diagnostic count");
        BarCounts[PERIOD_MN1]=0;
        Check(!readiness.isReady(logger) && Logs.Count==1,"same clamped percentage does not repeat log");
        BarCounts[PERIOD_MN1]=30;BarCounts[PERIOD_W1]=101;
        Check(!readiness.isReady(logger) && Logs.Last().Contains("progress=49%") && Logs.Last().Contains("bottleneck=W1"),"bottleneck uses precise ratio, not tied integer percentage");
        foreach(int frame in Periods) BarCounts[frame]=1000000;
        Check(readiness.isReady(logger) && Logs.Last().Contains("progress=100%"),"excess history caps progress at 100 percent");
        ''')

    def test_reset_and_reinitialize_discard_prior_progress_requests_and_range(self):
        self.execute(r'''
        ElliotHistoryReadiness readiness=Create();
        Synchronized[PERIOD_MN1]=false;
        Check(!readiness.isReady(logger) && Requests()==1,"seed a request marker");
        readiness.reset();
        Calls.Clear();Check(!readiness.isReady(logger) && !readiness.isWarmingUp(),"reset state is not ready or warming up");
        readiness.requestHistory();Check(Calls.Count==0,"reset state does not query or request series");
        Check(readiness.initialize(new MarketContext("EURUSD",PERIOD_H1),false),"reinitialize on new symbol and timeframe");
        Calls.Clear();Logs.Clear();readiness.requestHistory();
        Check(Calls[0]=="request:EURUSD:49153,32769,16408,16388,16385:500","new range excludes lower timeframes and old symbol");
        Check(readiness.isWarmingUp() && !readiness.isReady(logger) && Requests()==2,"reset removes previous per-bar duplicate marker");
        Synchronized[PERIOD_MN1]=true;Check(readiness.isReady(logger) && !readiness.isWarmingUp(),"new range can complete");
        Check(readiness.initialize(new MarketContext("GBPJPY",PERIOD_M5),false) && readiness.isWarmingUp(),"initialize itself resets completed progress");
        Check(!readiness.initialize(new MarketContext("USDJPY",2),false),"unsupported target timeframe fails initialization");
        Calls.Clear();readiness.requestHistory();
        Check(!readiness.isReady(logger) && Calls.Count==0,"failed initialization cannot use stale history state");
        ''')


class ElliotHistoryReadinessWiringTests(unittest.TestCase):
    """Source contracts only; these do not execute the full indicator Controller."""

    @classmethod
    def setUpClass(cls):
        cls.controller = CONTROLLER.read_text(encoding="utf-8-sig")

    def test_initialize_and_destroy_keep_request_order_and_reset_state(self):
        initialize = code_only(method(self.controller, "initialize"))
        positions = [initialize.index(token) for token in (
            "this.destroy()", "this.historyReadiness.initialize(",
            "SymbolSelect(", "EventSetTimer(", "this.historyReadiness.requestHistory()",
            "this.createControllers()",
        )]
        self.assertEqual(positions, sorted(positions))
        self.assertIn("this.historyReadiness.reset();", method(self.controller, "destroy"))
        self.assertEqual(code_only(method(self.controller, "isAnalysisDataReady")).strip(),
                         "return this.historyReadiness.isReady(this.logger);")

    def test_on_calculate_waits_before_chart_update_and_forwards_readiness(self):
        body = method(self.controller, "onCalculate")
        masked = code_only(body)
        gate = re.search(r"if\s*\(this\.historyReadiness\.isWarmingUp\(\)\)\s*\{", masked)
        self.assertIsNotNone(gate)
        end = block_end(masked, gate.end() - 1)
        waiting = masked[gate.end():end]
        self.assertIn("isAnalysisDataReady = this.isAnalysisDataReady();", waiting)
        self.assertRegex(waiting, r"if\s*\(!isAnalysisDataReady\)\s*\{\s*this\.chartController\.endProcessingTimeUpdateBatch\(\);\s*return 0;")
        self.assertLess(end, masked.index("this.chartController.updateOnCalculate("))
        self.assertLess(masked.index("this.chartController.updateOnCalculate("), masked.index("this.execute(isAnalysisDataReady)"))

    def test_analysis_failure_does_not_advance_processed_bar(self):
        body = method(self.controller, "execute")
        masked = code_only(body)
        readiness = masked.index("if (!fromAnalysisDataReady && !this.isAnalysisDataReady())")
        analysis = re.search(r"if\s*\(!this\.analysisController\.analyze\([^{}]+\)\)\s*\{", masked)
        self.assertIsNotNone(analysis)
        self.assertLess(readiness, analysis.start())
        end = block_end(masked, analysis.end() - 1)
        failure = masked[analysis.end():end]
        self.assertIn("this.endCurrencyStrengthRedrawBatch();", failure)
        self.assertIn("return;", failure)
        self.assertNotIn("lastProcessedBarTime", failure)
        self.assertGreater(masked.index("this.lastProcessedBarTime = currentBarTime;"), end)
        readiness_source = code_only(READINESS.read_text(encoding="utf-8-sig"))
        for execution_state in ("lastProcessedBarTime", "gapWaitingChartBarTime", "gapWaitingM5BarTime", "CopyBuffer"):
            self.assertNotIn(execution_state, readiness_source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
