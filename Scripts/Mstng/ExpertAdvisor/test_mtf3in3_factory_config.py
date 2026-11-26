"""Execute production Factory/configuration code with recording constructors.

MQL syntax is adapted to C#. Strategy constructors record the selected type,
context and forwarded arguments; these tests do not execute trading decisions.
The three indicator call-site configuration blocks are also production code.
"""

from pathlib import Path
import re
import sys
import unittest


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/Mstng/Database"))
from test_m5_observation_history_reader import block_end, code_only, method, run_csharp


DIRECTORY = ROOT / "Include/Mstng/ExpertAdvisor"
FACTORY = DIRECTORY / "ExpertAdvisorMtf3In3Factory.mqh"
CONFIG = DIRECTORY / "ExpertAdvisorMtf3In3Config.mqh"
FIELDS = (
    "isDrawArrow", "h1W1ConfirmationMode", "h1DirectionAlignmentMode", "h1Ema200ConfirmationMode",
    "h1DirectionCorrectionEnabled", "m15H4MaxFibonacciExpansionPercent", "m15H1MaxFibonacciExpansionPercent",
    "h1Mn1AndW1Ema200Required", "h1H4WaveRestrictionEnabled", "m5Mn1AndW1Ema200Required",
    "m5D1ToM5EntryPolicyEnabled", "m5CurrencyStrengthMinimumRankDifference",
    "m15CurrencyEma200DistanceEnabled", "m15LongMediumCurrencyStrengthEnabled",
    "m1M5AndM1WavePolicyEnabled", "m1DirectionCorrectionEnabled",
)


def syntax(source):
    source = re.sub(r"\bconst\s+", "", source)
    source = re.sub(r"\bH1(?:W1Confirmation|DirectionAlignment|Ema200Confirmation)Mode\b", "int", source)
    source = re.sub(r"\b(\w+)\s*&\s*(\w+)", r"\1 \2", source)
    source = re.sub(r"\bExpertAdvisorMTF_3in3\s*\*", "ExpertAdvisorMTF_3in3 ", source)
    source = source.replace("::", ".").replace("NULL", "null")
    source = re.sub(r"\bExpertAdvisorMtf3In3Config\s+(\w+)\s*;",
                    r"ExpertAdvisorMtf3In3Config \1 = new ExpertAdvisorMtf3In3Config();", source)
    return source


def class_fixture(source, name):
    opening = re.search(r"\b(?:class|struct) " + name + r"\s*\{", source).end() - 1
    body = source[opening + 1:block_end(code_only(source), opening)]
    body = re.sub(r"\b(?:public|private|protected)\s*:", "", body)
    body = syntax(body)
    body = re.sub(r"^(\s{4})(?=(?:static\s+)?(?:bool|int|double|void|ExpertAdvisorMTF_3in3|" + name + r")\b)",
                  r"\1public ", body, flags=re.M)
    return "public class " + name + " : MqlApi {\n" + body + "\n}\n"


API = r'''
using System;
using System.Globalization;
using System.Linq;
public class MqlApi {
    public const int PERIOD_CURRENT=0,PERIOD_M1=1,PERIOD_M5=5,PERIOD_M15=15,
        PERIOD_H1=16385,PERIOD_H4=16388,PERIOD_D1=16408,PERIOD_W1=32769,PERIOD_MN1=49153;
    public const int H1_W1_CONFIRMATION_OFF=0,H1_W1_CONFIRMATION_OBSERVE_ONLY=1,
        H1_W1_CONFIRMATION_DIRECTION_OR_EMA200=2,H1_W1_CONFIRMATION_DIRECTION_AND_EMA200=3;
    public const int H1_DIRECTION_ALIGNMENT_D1_TO_H1=0,H1_DIRECTION_ALIGNMENT_MN1_TO_H1_OBSERVE=1,
        H1_DIRECTION_ALIGNMENT_MN1_TO_H1_REQUIRED=2,H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED=3;
    public const int H1_EMA200_CONFIRMATION_H1_ONLY=0,H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED=1,
        H1_EMA200_CONFIRMATION_H1_AND_H4_AND_D1_REQUIRED=2;
}
public class MarketContext {
    public int timeFrame; public string symbolName;
    public MarketContext(int frame) { timeFrame=frame;symbolName="EURJPY"; }
}
public class ExpertAdvisorMTF_3in3 {
    public MarketContext Context;public object[] Args;
    public ExpertAdvisorMTF_3in3(MarketContext context,params object[] args) { Context=context;Args=args; }
    public string Signature() {
        return GetType().Name+"|"+Context.symbolName+"|"+Context.timeFrame+"|"+
            String.Join("|",Args.Select(value=>Convert.ToString(value,CultureInfo.InvariantCulture)));
    }
}
public class ExpertAdvisorMtf3In3H1 : ExpertAdvisorMTF_3in3 {
    public ExpertAdvisorMtf3In3H1(MarketContext context,params object[] args) : base(context,args) {}
}
public class ExpertAdvisorMtf3In3M15 : ExpertAdvisorMTF_3in3 {
    public ExpertAdvisorMtf3In3M15(MarketContext context,params object[] args) : base(context,args) {}
}
public class ExpertAdvisorMtf3In3M5 : ExpertAdvisorMTF_3in3 {
    public ExpertAdvisorMtf3In3M5(MarketContext context,params object[] args) : base(context,args) {}
}
public class ExpertAdvisorMtf3In3M1 : ExpertAdvisorMTF_3in3 {
    public ExpertAdvisorMtf3In3M1(MarketContext context,params object[] args) : base(context,args) {}
}
'''


def production_fixture():
    return (API + class_fixture(CONFIG.read_text(encoding="utf-8-sig"), "ExpertAdvisorMtf3In3Config")
            + class_fixture(FACTORY.read_text(encoding="utf-8-sig"), "ExpertAdvisorMtf3In3Factory"))


def configuration_block(source):
    """Keep the actual assignments and factory call, excluding lifecycle code."""
    start = re.search(r"\bExpertAdvisorMtf3In3Config\s+strategyConfig\s*;", source).start()
    call = source.index("ExpertAdvisorMtf3In3Factory::create(", start)
    end = source.index(";", call) + 1
    return syntax(source[start:end])


def caller_fixture():
    normal = (ROOT / "Include/Mstng/Indicator/ZigZagElliot/Mtf3In3AlertController.mqh").read_text(encoding="utf-8-sig")
    all_source = (ROOT / "Include/Mstng/Indicator/ZigZagElliot/Mtf3In3AlertAllController.mqh").read_text(encoding="utf-8-sig")
    monitor = (ROOT / "Include/Mstng/Indicator/ZigZagElliotMonitor/ZigZagElliotMonitorEvaluator.mqh").read_text(encoding="utf-8-sig")
    source = '''
public class NormalCaller : MqlApi {
    MarketContext marketContext;ExpertAdvisorMtf3In3Config config;
    ExpertAdvisorMTF_3in3 expertAdvisorMtf3In3;
    public ExpertAdvisorMTF_3in3 Run(MarketContext context,ExpertAdvisorMtf3In3Config input) {
        this.marketContext=context;this.config=input;
'''
    source += configuration_block(method(normal, "initialize")) + "\nreturn this.expertAdvisorMtf3In3; } }\n"
    source += '''
public class ListCaller : MqlApi {
    ExpertAdvisorMTF_3in3 expertAdvisor;
    public ExpertAdvisorMTF_3in3 Run(MarketContext context,ExpertAdvisorMtf3In3Config fromConfig) {
'''
    source += configuration_block(method(all_source, "initialize")) + "\nreturn this.expertAdvisor; } }\n"
    source += '''
public class MonitorConfig { public ExpertAdvisorMtf3In3Config entryConfig; }
public class MonitorCaller : MqlApi {
    MonitorConfig config=new MonitorConfig();
    public ExpertAdvisorMTF_3in3 Run(MarketContext fromMarketContext,ExpertAdvisorMtf3In3Config input) {
        this.config.entryConfig=input;
'''
    source += configuration_block(monitor) + "\n} }\n"
    return source


SETUP = r'''
public class FactoryFixture : MqlApi {
    static int checks;
    static int[] Frames={PERIOD_H1,PERIOD_M15,PERIOD_M5,PERIOD_M1,PERIOD_H4,PERIOD_D1,PERIOD_W1,PERIOD_MN1,2};
    static void Check(bool value,string message) { checks++;if(!value) throw new Exception(message); }
    static void CheckArgs(ExpertAdvisorMTF_3in3 actual,string kind,MarketContext context,params object[] args) {
        Check(actual.GetType().Name==kind,"selected "+kind+" for "+context.timeFrame);
        Check(Object.ReferenceEquals(actual.Context,context),"context is forwarded without reconstruction");
        Check(actual.Args.SequenceEqual(args),"constructor argument mapping: "+actual.Signature());
    }
    static ExpertAdvisorMtf3In3Config Config(int mask) {
        ExpertAdvisorMtf3In3Config config=new ExpertAdvisorMtf3In3Config();
        config.isDrawArrow=(mask&1)!=0;config.h1DirectionCorrectionEnabled=(mask&2)!=0;
        config.h1Mn1AndW1Ema200Required=(mask&4)!=0;config.h1H4WaveRestrictionEnabled=(mask&8)!=0;
        config.m5Mn1AndW1Ema200Required=(mask&16)!=0;config.m5D1ToM5EntryPolicyEnabled=(mask&32)!=0;
        config.m15CurrencyEma200DistanceEnabled=(mask&64)!=0;config.m15LongMediumCurrencyStrengthEnabled=(mask&128)!=0;
        config.m1M5AndM1WavePolicyEnabled=(mask&256)!=0;config.m1DirectionCorrectionEnabled=(mask&512)!=0;
        config.h1W1ConfirmationMode=mask%4;config.h1DirectionAlignmentMode=(mask+1)%4;
        config.h1Ema200ConfirmationMode=mask%3;
        config.m15H4MaxFibonacciExpansionPercent=91.25+mask;
        config.m15H1MaxFibonacciExpansionPercent=182.5+mask;
        config.m5CurrencyStrengthMinimumRankDifference=mask%8+1;
        return config;
    }
    static ExpertAdvisorMTF_3in3 Legacy(MarketContext context,ExpertAdvisorMtf3In3Config config) {
        return ExpertAdvisorMtf3In3Factory.create(context,
            config.isDrawArrow,config.h1W1ConfirmationMode,config.h1DirectionAlignmentMode,
            config.h1Ema200ConfirmationMode,config.h1DirectionCorrectionEnabled,
            config.m15H4MaxFibonacciExpansionPercent,config.m15H1MaxFibonacciExpansionPercent,
            config.h1Mn1AndW1Ema200Required,config.h1H4WaveRestrictionEnabled,
            config.m5Mn1AndW1Ema200Required,config.m5D1ToM5EntryPolicyEnabled,
            config.m5CurrencyStrengthMinimumRankDifference,config.m15CurrencyEma200DistanceEnabled,
            config.m15LongMediumCurrencyStrengthEnabled,config.m1M5AndM1WavePolicyEnabled,
            config.m1DirectionCorrectionEnabled);
    }
'''


class Mtf3In3FactoryConfigTests(unittest.TestCase):
    def execute(self, body, callers=False):
        source = production_fixture()
        if callers:
            source += caller_fixture()
        source += SETUP + "public static string Run() {\n" + body
        source += '\nreturn "PASS "+checks+" factory assertions"; } }\n'
        self.assertRegex(run_csharp(source, "[FactoryFixture]::Run()\n"), r"PASS \d+ factory assertions")

    def test_defaults_and_partial_legacy_calls_remain_compatible(self):
        values = ",".join("config." + name for name in FIELDS)
        self.execute('''
        ExpertAdvisorMtf3In3Config config=new ExpertAdvisorMtf3In3Config();
        Check(new object[]{''' + values + '''}.SequenceEqual(new object[]{true,1,0,0,false,0.0,0.0,false,true,false,false,4,false,false,false,false}),"all sixteen defaults retain old API values");
        foreach(int frame in Frames) {
            MarketContext context=new MarketContext(frame);
            config=new ExpertAdvisorMtf3In3Config();
            Check(ExpertAdvisorMtf3In3Factory.create(context).Signature()==ExpertAdvisorMtf3In3Factory.create(context,config).Signature(),"one-argument default call");
            config.isDrawArrow=false;
            Check(ExpertAdvisorMtf3In3Factory.create(context,false).Signature()==ExpertAdvisorMtf3In3Factory.create(context,config).Signature(),"two-argument legacy call");
            config.h1W1ConfirmationMode=3;config.h1DirectionAlignmentMode=2;config.h1Ema200ConfirmationMode=2;
            Check(ExpertAdvisorMtf3In3Factory.create(context,false,3,2,2).Signature()==ExpertAdvisorMtf3In3Factory.create(context,config).Signature(),"five-argument EA call");
            config.h1DirectionCorrectionEnabled=true;config.m15H4MaxFibonacciExpansionPercent=161.8;config.m15H1MaxFibonacciExpansionPercent=261.8;
            Check(ExpertAdvisorMtf3In3Factory.create(context,false,3,2,2,true,161.8,261.8).Signature()==ExpertAdvisorMtf3In3Factory.create(context,config).Signature(),"eight-argument M15 EA call");
        }
        ''')

    def test_dispatch_and_constructor_arguments_match_each_timeframe_policy(self):
        self.execute(r'''
        foreach(int mask in new int[]{0,1,2,4,8,16,32,64,128,256,512,1023}) {
            ExpertAdvisorMtf3In3Config config=Config(mask);
            foreach(int frame in Frames) {
                MarketContext context=new MarketContext(frame);
                ExpertAdvisorMTF_3in3 actual=ExpertAdvisorMtf3In3Factory.create(context,config);
                if(frame==PERIOD_H1) CheckArgs(actual,"ExpertAdvisorMtf3In3H1",context,config.isDrawArrow,config.h1DirectionCorrectionEnabled,config.h1Mn1AndW1Ema200Required,config.h1H4WaveRestrictionEnabled);
                else if(frame==PERIOD_M15) CheckArgs(actual,"ExpertAdvisorMtf3In3M15",context,config.isDrawArrow,config.h1DirectionCorrectionEnabled,config.m15H4MaxFibonacciExpansionPercent,config.m15H1MaxFibonacciExpansionPercent,config.h1Mn1AndW1Ema200Required,config.h1H4WaveRestrictionEnabled,config.m15CurrencyEma200DistanceEnabled,config.m15LongMediumCurrencyStrengthEnabled);
                else if(frame==PERIOD_M5) CheckArgs(actual,"ExpertAdvisorMtf3In3M5",context,config.isDrawArrow,config.m5Mn1AndW1Ema200Required,config.m5D1ToM5EntryPolicyEnabled,config.m5CurrencyStrengthMinimumRankDifference);
                else if(frame==PERIOD_M1 && config.m1M5AndM1WavePolicyEnabled) CheckArgs(actual,"ExpertAdvisorMtf3In3M1",context,config.isDrawArrow,config.h1W1ConfirmationMode,config.h1DirectionAlignmentMode,config.h1Ema200ConfirmationMode,config.m1DirectionCorrectionEnabled);
                else CheckArgs(actual,"ExpertAdvisorMTF_3in3",context,config.isDrawArrow,config.h1W1ConfirmationMode,config.h1DirectionAlignmentMode,config.h1Ema200ConfirmationMode);
            }
        }
        ''')

    def test_legacy_wrapper_forwards_every_flag_combination(self):
        self.execute(r'''
        for(int mask=0;mask<1024;mask++) {
            ExpertAdvisorMtf3In3Config config=Config(mask);
            foreach(int frame in Frames) {
                MarketContext context=new MarketContext(frame);
                Check(Legacy(context,config).Signature()==ExpertAdvisorMtf3In3Factory.create(context,config).Signature(),"all settings survive legacy wrapper: "+mask+"/"+frame);
            }
        }
        ''')

    def test_normal_monitor_and_list_configuration_preserve_caller_differences(self):
        self.execute(r'''
        NormalCaller normal=new NormalCaller();MonitorCaller monitor=new MonitorCaller();ListCaller list=new ListCaller();
        foreach(int mask in new int[]{0,1,2,4,8,16,32,64,128,256,512,1023}) {
            foreach(int frame in Frames) {
                MarketContext context=new MarketContext(frame);
                ExpertAdvisorMtf3In3Config input=Config(mask),expected=Config(mask);
                expected.isDrawArrow=true;expected.m1M5AndM1WavePolicyEnabled=frame==PERIOD_M1;
                Check(normal.Run(context,input).Signature()==ExpertAdvisorMtf3In3Factory.create(context,expected).Signature(),"normal caller copies settings and selects M1 only on M1");
                expected.isDrawArrow=false;expected.m1M5AndM1WavePolicyEnabled=true;
                Check(monitor.Run(context,input).Signature()==ExpertAdvisorMtf3In3Factory.create(context,expected).Signature(),"monitor caller disables arrows and enables M1 policy");
            }
            MarketContext h1=new MarketContext(PERIOD_H1);
            CheckArgs(list.Run(h1,Config(mask)),"ExpertAdvisorMtf3In3H1",h1,false,false,false,true);
        }
        ''', callers=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
