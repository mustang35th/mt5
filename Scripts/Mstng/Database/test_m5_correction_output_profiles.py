"""Exercise the actual output validators with complete correction fixtures.

The existing MQL predicate translator executes the production guards, so this
checks acceptance across snapshot, mail and tooltip paths without sending mail.
"""
import re
import unittest
from types import SimpleNamespace as Record

from test_h1_alert_correction_storage import CONSTANTS, FRAMES, method, source, translate_check


def validator(relative, name, arguments):
    body = method(source(relative), name)
    body = re.sub(r'\bElliot\s*\*\s*(\w+)\s*=', r'\1 =', body)
    body = body.replace('NULL', 'None').replace('Constant::getBuySell', 'getSide').replace('""', 'emptyText')
    result = translate_check(body, arguments)
    result.__globals__.update(PERIOD_CURRENT=0, emptyText='', getSide=lambda buy: 'BUY' if buy else 'SELL')
    return result


def analysis(current, correction, buy, corrected):
    count = {CONSTANTS['PERIOD_H1']: 5, CONSTANTS['PERIOD_M15']: 6}.get(current, 7)
    frames = {}
    for timeframe in FRAMES[:count]:
        direction = buy if corrected or timeframe != correction else not buy
        point = Record(elliotLabel='3')
        frames[timeframe] = Record(
            marketContext=Record(timeFrame=timeframe, symbolName='USDJPY'),
            isBuy=direction, buySellLabel='BUY' if direction else 'SELL',
            currentOhlcBarTime=100, previousOhlcBarTime=90,
            getLatestWave=lambda: object(), getLatestPoint=lambda point=point: point)
    return Record(
        marketContext=Record(timeFrame=current, symbolName='USDJPY'),
        isAnalysisSucceeded=True, elliotCurrent=frames[current],
        elliotList=Record(Total=lambda: count), getElliot=frames.get,
        tradeTimeInfo=Record(serverTime=100, jstTime=100), todayRate=Record(bid=150, ask=150.003))


class CorrectionOutputProfileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.snapshot = staticmethod(validator('ExpertAdvisor/Mtf3In3AlertSnapshotBuilder.mqh',
            'isJudgmentSnapshotValid', 'fromOriginal, fromJudgment, fromResult, fromCorrectionTimeFrame, fromJudgmentAlertText'))
        cls.mail = staticmethod(validator('Mail/Mail.mqh', 'isCorrectionMailValid',
            'fromSource, fromJudgment, fromCorrectionTimeFrame, fromAlertText'))
        tooltip = method(source('Draw/DrawZigZagElliotLiveAlertTooltip.mqh'), 'apply')
        start = tooltip.index('bool isM5Correction')
        end = tooltip.index('Elliot *original', start)
        cls.tooltip = staticmethod(translate_check(tooltip[start:end]+'return true;',
            'marker, fromCorrectionTimeFrame'))

    def outputs(self, current, correction, buy, mutate=None):
        original = analysis(current, correction, buy, False)
        selected = analysis(current, correction, buy, True)
        if mutate:
            mutate(original, selected)
        result = Record(isAlert=True, isBuy=buy, currentElliotLabel='3')
        return (self.snapshot(original, selected, result, correction, 'entry'),
                self.mail(original, selected, correction, 'entry'))

    def test_each_output_accepts_only_supported_single_corrections(self):
        profiles = {5: ('PERIOD_D1', 'PERIOD_H4', 'PERIOD_H1', 'PERIOD_M15'),
                    15: ('PERIOD_D1', 'PERIOD_H4', 'PERIOD_H1'),
                    CONSTANTS['PERIOD_H1']: ('PERIOD_D1', 'PERIOD_H4')}
        for current, names in profiles.items():
            allowed = {CONSTANTS[name] for name in names}
            for correction in FRAMES[:7]:
                for buy in (False, True):
                    with self.subTest(current=current, correction=correction, buy=buy):
                        expected = correction in allowed
                        self.assertEqual((expected, expected), self.outputs(current, correction, buy))
                        self.assertEqual(expected, self.tooltip(Record(timeFrame=current), correction))

    def test_m5_d1_rejects_second_opposing_leg(self):
        for other in ('PERIOD_H4', 'PERIOD_H1', 'PERIOD_M15'):
            for buy in (False, True):
                def mutate(original, selected):
                    for item in (original, selected):
                        frame = item.getElliot(CONSTANTS[other])
                        frame.isBuy = not buy
                        frame.buySellLabel = 'SELL' if buy else 'BUY'
                with self.subTest(other=other, buy=buy):
                    self.assertEqual((False, False), self.outputs(5, CONSTANTS['PERIOD_D1'], buy, mutate))

    def test_m5_d1_rejects_different_snapshot_time(self):
        def mutate(original, selected):
            selected.tradeTimeInfo.serverTime += 1
        self.assertEqual((False, False), self.outputs(5, CONSTANTS['PERIOD_D1'], True, mutate))


if __name__ == '__main__':
    unittest.main()
