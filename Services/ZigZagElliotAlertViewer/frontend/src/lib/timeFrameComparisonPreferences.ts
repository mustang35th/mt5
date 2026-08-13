export const TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY =
  "zigzagElliotAlertViewer.timeframeComparisonColumnGroups.v1";

export const TIME_FRAME_COMPARISON_COLUMN_GROUP_STATE_VERSION = 1;

export const TIME_FRAME_COMPARISON_COLLAPSIBLE_GROUP_IDS = [
  "wave",
  "price",
  "fibo_expansion",
  "oscillator_stochastic",
  "trend_ema",
] as const;

export type TimeFrameComparisonColumnGroupId =
  typeof TIME_FRAME_COMPARISON_COLLAPSIBLE_GROUP_IDS[number];

export type TimeFrameComparisonColumnGroupState = Record<
  TimeFrameComparisonColumnGroupId,
  boolean
>;

interface StoredTimeFrameComparisonColumnGroupState {
  version: number;
  groups: TimeFrameComparisonColumnGroupState;
}

type StorageReader = Pick<Storage, "getItem">;
type StorageWriter = Pick<Storage, "setItem">;
type StorageRemover = Pick<Storage, "removeItem">;

/**
 * 初期の列グループ開閉状態を返します。
 *
 * @return 全詳細グループを閉じた状態
 */
export function defaultTimeFrameComparisonColumnGroupState(): TimeFrameComparisonColumnGroupState {
  return {
    wave: false,
    price: false,
    fibo_expansion: false,
    oscillator_stochastic: false,
    trend_ema: false,
  };
}

/**
 * 保存済みの列グループ開閉状態を読み込みます。
 *
 * @param fromStorage 読み込み元ストレージ
 * @return 検証済みの列グループ開閉状態
 */
export function readTimeFrameComparisonColumnGroupState(
  fromStorage?: StorageReader,
): TimeFrameComparisonColumnGroupState {
  const initialState = defaultTimeFrameComparisonColumnGroupState();

  try {
    const storage = fromStorage ?? browserStorage();
    const storedText = storage?.getItem(
      TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY,
    );
    if (!storedText) return initialState;

    const storedValue: unknown = JSON.parse(storedText);
    if (!isRecord(storedValue)) return initialState;
    if (storedValue.version !== TIME_FRAME_COMPARISON_COLUMN_GROUP_STATE_VERSION) {
      return initialState;
    }
    if (!isRecord(storedValue.groups)) return initialState;

    const restoredState = { ...initialState };
    for (const groupId of TIME_FRAME_COMPARISON_COLLAPSIBLE_GROUP_IDS) {
      const open = storedValue.groups[groupId];
      if (typeof open !== "boolean") return initialState;
      restoredState[groupId] = open;
    }
    return restoredState;
  } catch {
    return initialState;
  }
}

/**
 * 列グループ開閉状態を保存します。
 *
 * @param fromState 保存する開閉状態
 * @param toStorage 保存先ストレージ
 */
export function writeTimeFrameComparisonColumnGroupState(
  fromState: TimeFrameComparisonColumnGroupState,
  toStorage?: StorageWriter,
): void {
  try {
    const storage = toStorage ?? browserStorage();
    if (!storage) return;

    const storedState: StoredTimeFrameComparisonColumnGroupState = {
      version: TIME_FRAME_COMPARISON_COLUMN_GROUP_STATE_VERSION,
      groups: defaultTimeFrameComparisonColumnGroupState(),
    };
    for (const groupId of TIME_FRAME_COMPARISON_COLLAPSIBLE_GROUP_IDS) {
      storedState.groups[groupId] = fromState[groupId] === true;
    }
    storage.setItem(
      TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY,
      JSON.stringify(storedState),
    );
  } catch {
    // Storageが利用できない場合もグリッド表示は継続します。
  }
}

/**
 * 保存済みの列グループ開閉状態を削除します。
 *
 * @param fromStorage 削除対象ストレージ
 */
export function clearTimeFrameComparisonColumnGroupState(
  fromStorage?: StorageRemover,
): void {
  try {
    const storage = fromStorage ?? browserStorage();
    storage?.removeItem(TIME_FRAME_COMPARISON_COLUMN_GROUP_STORAGE_KEY);
  } catch {
    // Storageが利用できない場合もグリッド表示は継続します。
  }
}

/**
 * ブラウザのlocalStorageを安全に取得します。
 *
 * @return 利用可能なlocalStorage
 */
function browserStorage(): Storage | null {
  if (typeof window === "undefined") return null;
  return window.localStorage;
}

/**
 * 値がオブジェクトかを判定します。
 *
 * @param fromValue 判定対象
 * @return オブジェクトの場合true
 */
function isRecord(fromValue: unknown): fromValue is Record<string, unknown> {
  return typeof fromValue === "object" && fromValue !== null;
}
