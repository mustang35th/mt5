"""Execute the production M1 wave predicates with deterministic C# fixtures.

Only MQL pointer declarations, NULL and ENUM_TIMEFRAMES syntax are adapted.
The actual branches, boolean operators, labels and method calls run unchanged.
This verifies the wave gate, not native MT5 analysis, the complete entry decision,
indicator data, trade execution or trading performance. No terminal is accessed.
"""

from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from test_h1_ea_tester_warmup_contract import ROOT, method


SOURCE = ROOT / "Include/Mstng/ExpertAdvisor/ExpertAdvisorMtf3In3M1.mqh"


def as_csharp(body):
    body = re.sub(r"\b(Elliot|Wave|ZigZagPoint)\s*\*", r"\1 ", body)
    body = re.sub(r"\bNULL\b", "null", body)
    return re.sub(r"\bENUM_TIMEFRAMES\b", "int", body)


FIXTURE = r'''
using System;
using System.Collections.Generic;

public class MarketContext { public int timeFrame; }
public class PointList {
    public List<ZigZagPoint> values = new List<ZigZagPoint>();
    public int Total() { return values.Count; }
    public ZigZagPoint At(int index) { return index >= 0 && index < Total() ? values[index] : null; }
}
public class ZigZagPoint {
    public string elliotLabel, subElliotLabel;
    public int elliotIndex, subElliotIndex;
    public bool isElliotAlphabet;
    public bool isNumeric() { return !isElliotAlphabet; }
}
public class Wave {
    public bool isMotive;
    public PointList zigZagPointList = new PointList();
    public ZigZagPoint latestPoint;
}
public class Elliot {
    public MarketContext marketContext = new MarketContext();
    public Wave latestWave;
    public Wave getLatestWave() { return latestWave; }
    public ZigZagPoint getLatestPoint() { return latestWave == null ? null : latestWave.latestPoint; }
}
public class WavePredicate {
    public const int PERIOD_CURRENT=0, PERIOD_M1=1, PERIOD_M5=5, PERIOD_M15=15, PERIOD_H1=16385;
    public MarketContext marketContext = new MarketContext { timeFrame=PERIOD_M1 };
    public Elliot elliotM5, elliotM1;
    public bool isEntryWave(Elliot fromElliot) { __ENTRY__ }
    public bool isTimeFrameWaveConditionMatched() { __PAIR__ }
}

public static class M1OddWaveFixture {
    static int assertions;
    static void Check(bool value, string message) {
        assertions++;
        if(!value) throw new Exception(message);
    }
    static Elliot Analysis(int frame, string label, bool motive=true, bool wave3Sub=false, bool hasWave3=true) {
        Wave wave=new Wave { isMotive=motive };
        if(hasWave3) wave.zigZagPointList.values.Add(new ZigZagPoint {
            elliotLabel="3", elliotIndex=3,
            subElliotIndex=wave3Sub ? 3 : 0, subElliotLabel=wave3Sub ? "3" : ""
        });
        wave.latestPoint=new ZigZagPoint { elliotLabel=label, subElliotLabel="", elliotIndex=5 };
        wave.zigZagPointList.values.Add(wave.latestPoint);
        return new Elliot { marketContext=new MarketContext { timeFrame=frame }, latestWave=wave };
    }
    static WavePredicate Pair(string m5, string m1) {
        return new WavePredicate { elliotM5=Analysis(5,m5), elliotM1=Analysis(1,m1) };
    }
    public static string Run() {
        assertions=0;
        string[] allowed={"1","3","5"};
        foreach(string m5 in allowed) foreach(string m1 in allowed) {
            Check(Pair(m5,m1).isTimeFrameWaveConditionMatched(), "allowed pair "+m5+"/"+m1);
        }
        string[] denied={"0","2","4","A","B","C","","a"," 1","1 ","1-3"};
        foreach(string label in denied) foreach(string accepted in allowed) {
            Check(!Pair(label,accepted).isTimeFrameWaveConditionMatched(), "M5 rejected "+label);
            Check(!Pair(accepted,label).isTimeFrameWaveConditionMatched(), "M1 rejected "+label);
        }
        foreach(int frame in new int[]{1,5}) {
            WavePredicate gate=Pair("1","1");
            Check(!gate.isEntryWave(null), "null analysis");
            Elliot missing=Analysis(frame,"1"); missing.latestWave=null;
            Check(!gate.isEntryWave(missing), "missing latest wave "+frame);
            missing=Analysis(frame,"3"); missing.latestWave.latestPoint=null;
            Check(!gate.isEntryWave(missing), "missing latest point "+frame);
            foreach(bool motive in new bool[]{true,false}) foreach(bool hasThree in new bool[]{true,false})
            foreach(bool sub in new bool[]{true,false}) {
                Elliot five=Analysis(frame,"5",motive,sub,hasThree);
                five.latestWave.latestPoint.subElliotIndex=2;
                five.latestWave.latestPoint.subElliotLabel="B";
                Check(gate.isEntryWave(five), "5 accepts motive/history/sub combinations "+frame);
                if(frame==5) gate.elliotM5=five; else gate.elliotM1=five;
                Check(gate.isTimeFrameWaveConditionMatched(), "5 combination applies to pair "+frame);
            }
            Elliot mainTwo=Analysis(frame,"2");
            mainTwo.latestWave.latestPoint.subElliotLabel="5";
            mainTwo.latestWave.latestPoint.subElliotIndex=5;
            Check(!gate.isEntryWave(mainTwo), "subwave 5 cannot replace main wave 2");
        }
        foreach(int frame in new int[]{0,15,30,16385,16388,16408,32769,49153}) {
            Check(!Pair("1","1").isEntryWave(Analysis(frame,"1")), "unrelated timeframe "+frame);
        }
        foreach(bool first in new bool[]{true,false}) {
            WavePredicate gate=Pair("1","3");
            if(first) gate.elliotM5=null; else gate.elliotM1=null;
            Check(!gate.isTimeFrameWaveConditionMatched(), "missing pair analysis "+first);
            foreach(bool waveMissing in new bool[]{true,false}) {
                gate=Pair("1","3");
                Elliot missing=first ? gate.elliotM5 : gate.elliotM1;
                if(waveMissing) missing.latestWave=null; else missing.latestWave.latestPoint=null;
                Check(!gate.isTimeFrameWaveConditionMatched(), "missing pair wave/point "+first+"/"+waveMissing);
            }
            foreach(int frame in new int[]{1,5,15,16385}) {
                if(frame==(first ? 5 : 1)) continue;
                gate=Pair("1","3");
                if(first) gate.elliotM5=Analysis(frame,"1"); else gate.elliotM1=Analysis(frame,"3");
                Check(!gate.isTimeFrameWaveConditionMatched(), "wrong pair slot "+first+"/"+frame);
            }
        }
        return "PASS "+assertions+" wave gate assertions";
    }
}
'''


class M1OddWaveTests(unittest.TestCase):
    def test_actual_wave_predicates_with_independent_fixtures(self):
        powershell = shutil.which("powershell.exe")
        if powershell is None:
            self.skipTest("C# fixture requires Windows PowerShell Add-Type")
        source = SOURCE.read_text(encoding="utf-8-sig")
        fixture = FIXTURE.replace("__ENTRY__", as_csharp(method(source, "isEntryWave")))
        fixture = fixture.replace("__PAIR__", as_csharp(method(source, "isTimeFrameWaveConditionMatched")))
        with tempfile.TemporaryDirectory(prefix="m1-odd-waves-") as directory:
            path = Path(directory)
            (path / "fixture.cs").write_text(fixture, encoding="utf-8-sig")
            (path / "run.ps1").write_text(
                "$ErrorActionPreference = 'Stop'\n"
                "Add-Type -Path (Join-Path $PSScriptRoot 'fixture.cs')\n"
                "[M1OddWaveFixture]::Run()\n", encoding="utf-8-sig")
            completed = subprocess.run(
                [powershell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                 "-File", str(path / "run.ps1")],
                capture_output=True, encoding="utf-8", errors="replace", timeout=30,
            )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertRegex(completed.stdout, r"PASS \d+ wave gate assertions")


if __name__ == "__main__":
    unittest.main()
