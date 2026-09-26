"""Display-only profit wiring and execution of production collector bodies.

The C# fixture translates MQL declarations/reference syntax only, retaining the
production loops, filters, arithmetic, error paths and cache conditions. MT5
account/position/clock reads are deterministic stubs; no terminal is accessed.
"""

from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from test_h1_ea_tester_warmup_contract import block_end, code_only, method

ROOT = Path(__file__).resolve().parents[3]
COLLECTOR = ROOT / "Include/MstngH1Ea/Presentation/H1EaFloatingProfitMonitor.mqh"


def collector_as_csharp(source):
    """Keep the class body intact except for explicit MQL/C# syntax differences."""
    start = source.index("class H1EaFloatingProfitMonitor")
    opening = source.index("{", start)
    source = source[start:block_end(code_only(source), opening) + 1]
    source = source.replace("class H1EaFloatingProfitMonitor", "class H1EaFloatingProfitMonitor : PositionApi")
    source = re.sub(r"(?m)^\s*(?:public|private|protected):", "", source)
    source = source.replace("const ", "").replace("::", ".")
    source = re.sub(r"\bdatetime\b", "long", source)
    source = re.sub(r"(\w+)\s+&(\w+)\[\]", r"\1[] \2", source)
    source = re.sub(r"(\w+)\s+&(\w+)", r"\1 \2", source)
    source = re.sub(r"(\w+)\s+(\w+)\[(\d+)\]\s*;", r"\1[] \2 = new \1[\3];", source)
    source = re.sub(r"\)\s*const\s*\{", ") {", source)
    source = re.sub(r"(?m)^(\s*)((?:bool|void|int|long|ulong|string|double)\s+\w+\s*\(|H1EaFloatingProfitMonitor\s*\()",
                    r"\1public \2", source)
    source = re.sub(r"(PositionGet(?:String|Integer|Double)\([^,()]+,)\s*([\w.]+)\)", r"\1 ref \2)", source)
    return source


CSHARP_API = r'''
using System;
using System.Collections.Generic;
public class H1EaRunEntity { public string symbolName; public string magicNumber; }
public class H1EaMonitorSymbolState {
    public string symbolName; public bool floatingProfitKnown;
    public double floatingProfit; public int positionCount;
}
public class H1EaMonitorState {
    public H1EaMonitorSymbolState[] symbols = new H1EaMonitorSymbolState[28];
    public int symbolCount = 28; public bool floatingProfitKnown;
    public double floatingProfit; public int positionCount;
    public string accountCurrency; public int currencyDigits; public long floatingProfitTime;
    public H1EaMonitorState() { for (int i=0;i<28;i++) symbols[i]=new H1EaMonitorSymbolState(); }
}
public class Position {
    public string symbol; public long magic; public double profit, swap;
    public Position(string symbol, long magic, double profit, double swap) {
        this.symbol=symbol; this.magic=magic; this.profit=profit; this.swap=swap;
    }
}
public static class H1EaClock { public static ulong milliseconds() { return PositionApi.now; } }
public static class H1EaTextUtil {
    public static ulong parseTicket(string value) { ulong result; return UInt64.TryParse(value,out result)?result:0; }
}
public class PositionApi {
    public const int POSITION_SYMBOL=1, POSITION_MAGIC=2, POSITION_PROFIT=3, POSITION_SWAP=4;
    public const int ACCOUNT_CURRENCY=5, ACCOUNT_CURRENCY_DIGITS=6;
    public static ulong now; public static int stubDigits, selected, reads, error, failIndex, failProperty;
    public static string stubCurrency;
    public static List<Position> positions = new List<Position>();
    public static void Reset() {
        now=100000; stubDigits=3; selected=-1; reads=0; error=0; failIndex=-1; failProperty=0;
        stubCurrency="KWD"; positions.Clear();
    }
    public static int ArraySize(Array fromArray) { return fromArray.Length; }
    public static void ArrayInitialize<T>(T[] array, T value) { for(int i=0;i<array.Length;i++) array[i]=value; }
    public static int ArrayCopy<T>(T[] target, T[] source) { Array.Copy(source,target,source.Length); return source.Length; }
    public static long StringToInteger(string value) { long result; return Int64.TryParse(value,out result)?result:0; }
    public static int StringLen(string value) { return value == null ? 0 : value.Length; }
    public static bool MathIsValidNumber(double value) { return !Double.IsNaN(value) && !Double.IsInfinity(value); }
    public static void ResetLastError() { error=0; }
    public static int GetLastError() { return error; }
    public static long TimeCurrent() { return (long)(now/1000); }
    public static string AccountInfoString(int kind) { return stubCurrency; }
    public static long AccountInfoInteger(int kind) { return stubDigits; }
    public static int PositionsTotal() { return positions.Count; }
    public static ulong PositionGetTicket(int index) {
        reads++; selected=index;
        if(index==failIndex && failProperty==0) { error=1; return 0; }
        return (ulong)(index+1);
    }
    public static bool PositionSelectByTicket(ulong ticket) { selected=(int)ticket-1; return selected>=0&&selected<positions.Count; }
    public static bool ReadOk(int kind) { if(selected==failIndex&&kind==failProperty) { error=1; return false; } return true; }
    public static bool PositionGetString(int kind, ref string value) {
        if(!ReadOk(kind)) return false; value=positions[selected].symbol; return true;
    }
    public static string PositionGetString(int kind) { string value=""; PositionGetString(kind,ref value); return value; }
    public static bool PositionGetInteger(int kind, ref long value) {
        if(!ReadOk(kind)) return false; value=positions[selected].magic; return true;
    }
    public static long PositionGetInteger(int kind) { long value=0; PositionGetInteger(kind,ref value); return value; }
    public static bool PositionGetDouble(int kind, ref double value) {
        if(!ReadOk(kind)) return false; value=kind==POSITION_PROFIT?positions[selected].profit:positions[selected].swap; return true;
    }
    public static double PositionGetDouble(int kind) { double value=0; PositionGetDouble(kind,ref value); return value; }
}
'''

CSHARP_CASES = r'''
public static class FloatingProfitFixture {
    static void Check(bool value, string message) { if(!value) throw new Exception(message); }
    static H1EaRunEntity[] Runs() {
        H1EaRunEntity[] runs = new H1EaRunEntity[28];
        for(int i=0;i<28;i++) runs[i]=new H1EaRunEntity {symbolName="S"+i,magicNumber=(1000+i).ToString()};
        return runs;
    }
    static H1EaMonitorState Snapshot() {
        H1EaMonitorState state=new H1EaMonitorState();
        for(int i=0;i<28;i++) state.symbols[i].symbolName="S"+i;
        return state;
    }
    static H1EaFloatingProfitMonitor Monitor() {
        H1EaFloatingProfitMonitor monitor=new H1EaFloatingProfitMonitor();
        monitor.initialize(Runs()); return monitor;
    }
    public static string Run() {
        PositionApi.Reset();
        PositionApi.positions.Add(new Position("S0",1000,10,-1));
        PositionApi.positions.Add(new Position("S0",1000,-4,.5));
        PositionApi.positions.Add(new Position("S27",1027,-7,-.5));
        PositionApi.positions.Add(new Position("S0",9999,999,999));
        PositionApi.positions.Add(new Position("FOREIGN",1000,999,999));
        H1EaFloatingProfitMonitor monitor=Monitor(); H1EaMonitorState state=Snapshot();
        monitor.updateAndCopy(state);
        Check(state.floatingProfitKnown && state.floatingProfit==-2 && state.positionCount==3,"scope/profit+swap/total");
        Check(state.symbols[0].floatingProfit==5.5 && state.symbols[0].positionCount==2,"multiple positions");
        Check(state.symbols[27].floatingProfit==-7.5 && state.symbols[1].floatingProfitKnown && state.symbols[1].floatingProfit==0,"all28/empty symbol");
        Check(state.accountCurrency=="KWD" && state.currencyDigits==3,"account currency precision");
        Check(PositionApi.reads==5,"one pass through positions");
        PositionApi.positions.Clear(); PositionApi.positions.Add(new Position("S27",1027,200,1));
        PositionApi.now=159999; monitor.updateAndCopy(state); monitor.updateAndCopy(state);
        Check(state.floatingProfit==-2 && PositionApi.reads==5,"59999ms/page redraw uses cache");
        PositionApi.now=160000; monitor.updateAndCopy(state);
        Check(state.floatingProfit==201 && state.positionCount==1 && PositionApi.reads==6,"60000ms refresh");
        PositionApi.positions.Clear(); PositionApi.now=220000; monitor.updateAndCopy(state);
        Check(state.floatingProfitKnown && state.floatingProfit==0 && state.positionCount==0,"no positions is known zero");
        int[] failures={0,PositionApi.POSITION_SYMBOL,PositionApi.POSITION_MAGIC,PositionApi.POSITION_PROFIT,PositionApi.POSITION_SWAP};
        foreach(int failure in failures) {
            PositionApi.Reset(); monitor=Monitor(); state=Snapshot();
            PositionApi.positions.Add(new Position("S0",1000,10,1));
            PositionApi.positions.Add(new Position("S27",1027,20,2));
            PositionApi.failIndex=1; PositionApi.failProperty=failure;
            monitor.updateAndCopy(state);
            Check(!state.floatingProfitKnown,"read failure cannot present partial total "+failure);
            Check(!state.symbols[27].floatingProfitKnown,"failed symbol cannot present partial rows "+failure);
            if(failure==0 || failure==PositionApi.POSITION_SYMBOL || failure==PositionApi.POSITION_MAGIC)
                Check(!state.symbols[0].floatingProfitKnown,"unknown ownership invalidates all rows "+failure);
            else Check(state.symbols[0].floatingProfitKnown && state.symbols[0].floatingProfit==11,"unaffected symbol retains valid value "+failure);
            PositionApi.failIndex=-1; PositionApi.now+=60000; monitor.updateAndCopy(state);
            Check(state.floatingProfitKnown && state.floatingProfit==33,"read failure recovers at next refresh "+failure);
        }
        PositionApi.Reset(); monitor=Monitor(); state=Snapshot();
        PositionApi.positions.Add(new Position("S0",1000,Double.NaN,0)); monitor.updateAndCopy(state);
        Check(!state.floatingProfitKnown,"invalid numeric result remains unknown");
        PanelProfitFixture panel=new PanelProfitFixture();
        Check(panel.formatFloatingProfit(12340,true,0)=="+12,340","JPY grouping/sign");
        Check(panel.formatFloatingProfit(-1234.5,true,2)=="-1,234.50","USD precision/sign");
        Check(panel.formatFloatingProfit(-.004,true,2)=="0.00" && panel.floatingProfitColor(-.004,true,2)==0,"rounded zero text/color");
        Check(panel.formatFloatingProfit(99,false,2)=="取得待ち" && panel.floatingProfitColor(99,false,2)==0,"unknown display");
        Check(panel.floatingProfitColor(1,true,2)==1 && panel.floatingProfitColor(-1,true,2)==2,"positive/negative colors");
        return "PASS aggregate scope currency single-scan cache-boundary empty read-failures recovery invalid-number";
    }
}
'''


class FloatingProfitContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.collector = COLLECTOR.read_text(encoding="utf-8-sig")
        cls.expert = (ROOT / "Experts/MstngH1EaAll.mq5").read_text(encoding="utf-8-sig")
        cls.panel = (ROOT / "Include/MstngH1Ea/Presentation/H1EaStatusPanel.mqh").read_text(encoding="utf-8-sig")

    def test_collector_is_display_only_and_has_no_broker_writes_or_database_access(self):
        body = code_only(self.collector[self.collector.index("class H1EaFloatingProfitMonitor"):])
        for forbidden in ("OrderSend", "OrderCheck", "Database", "persistence.", "strategy.",
                          "PositionClose", "PositionModify", "entryState", "EventSetTimer", "EventKillTimer"):
            self.assertNotIn(forbidden, body)
        for forbidden in ("PositionsTotal", "PositionGet", "AccountInfo"):
            self.assertNotIn(forbidden, code_only(self.panel))

    def test_only_visible_panel_copy_is_enriched_and_page_events_keep_sample_clock(self):
        body = code_only(method(self.expert, "updateStatusPanel"))
        chain = ["!statusPanel.isRefreshDue()", "controller.getMonitorState(state)",
                 "floatingProfitMonitor.updateAndCopy(state)", "statusPanel.draw(state)"]
        self.assertEqual([body.index(item) for item in chain], sorted(body.index(item) for item in chain))
        self.assertEqual(code_only(self.expert).count("floatingProfitMonitor.updateAndCopy("), 1)
        init = code_only(method(self.expert, "initializeFloatingProfitMonitor"))
        self.assertIn("controller.getRestorationState(i, state)", init)
        self.assertIn("runs[i] = state.run", init)
        self.assertIn("floatingProfitMonitor.initialize(runs)", init)
        events = code_only(method(self.panel, "onChartEvent"))
        self.assertIn("this.forceRefresh = true", events)
        self.assertNotIn("this.nextRefreshTick =", events)
        self.assertNotIn("floatingProfitMonitor", events)
        draw = code_only(method(self.panel, "draw"))
        self.assertRegex(draw, r"if \(now >= this.nextRefreshTick\) \{\s*this.nextRefreshTick = now \+ 60000;")
        self.assertIn("this.forceRefresh = false", draw)
        self.assertIn("this.canDraw() &&", code_only(method(self.panel, "isRefreshDue")))
        self.assertIn("return this.enabled && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE));",
                      code_only(method(self.panel, "canDraw")))

    def test_real_collector_bodies_aggregate_and_cache_with_deterministic_position_api(self):
        powershell = shutil.which("powershell.exe")
        if powershell is None:
            self.skipTest("C# execution fixture requires Windows PowerShell Add-Type")
        panel_helpers = r'''
public class PanelProfitFixture : PositionApi {
    const int clrSilver=0, clrDeepSkyBlue=1, clrLightCoral=2;
    static int MathMax(int a,int b) { return Math.Max(a,b); }
    static int MathMin(int a,int b) { return Math.Min(a,b); }
    static double MathAbs(double value) { return Math.Abs(value); }
    static double StringToDouble(string value) { return Double.Parse(value,System.Globalization.CultureInfo.InvariantCulture); }
    static string DoubleToString(double value,int digits) { return value.ToString("F"+digits,System.Globalization.CultureInfo.InvariantCulture); }
    static int StringFind(string value,string needle) { return value.IndexOf(needle,StringComparison.Ordinal); }
    static string StringSubstr(string value,int start) { return value.Substring(start); }
    static string StringSubstr(string value,int start,int length) { return value.Substring(start,length); }
'''
        panel_helpers += "public string formatFloatingProfit(double fromProfit,bool fromKnown,int fromDigits) {"
        panel_helpers += method(self.panel, "formatFloatingProfit") + "}\n"
        panel_helpers += "public int floatingProfitColor(double fromProfit,bool fromKnown,int fromDigits) {"
        panel_helpers += method(self.panel.replace("color floatingProfitColor", "int floatingProfitColor"), "floatingProfitColor") + "}}\n"
        source = CSHARP_API + collector_as_csharp(self.collector) + panel_helpers + CSHARP_CASES
        with tempfile.TemporaryDirectory(prefix="h1ea-floating-") as temp:
            path = Path(temp)
            (path / "fixture.cs").write_text(source, encoding="utf-8-sig")
            (path / "run.ps1").write_text(
                "$ErrorActionPreference = 'Stop'\n"
                "Add-Type -Path (Join-Path $PSScriptRoot 'fixture.cs')\n"
                "[FloatingProfitFixture]::Run()\n", encoding="utf-8-sig")
            result = subprocess.run([powershell, "-NoProfile", "-NonInteractive", "-File", str(path / "run.ps1")],
                                    capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS aggregate scope currency single-scan cache-boundary empty read-failures recovery invalid-number", result.stdout)


if __name__ == "__main__":
    unittest.main()
