import { useState, type MouseEvent } from "react";
import {
  Button,
  Checkbox,
  Menu,
  MenuItem,
  ToggleButton,
  ToggleButtonGroup,
} from "@mui/material";
import type { GridDensity } from "../lib/gridPreferences";

export interface GridColumnOption {
  colId: string;
  label: string;
  visible: boolean;
}

interface GridControlsProps {
  columns: GridColumnOption[];
  density: GridDensity;
  layoutReady: boolean;
  onDensityChange: (density: GridDensity) => void;
  onResetLayout: () => void;
  onToggleColumn: (colId: string, visible: boolean) => void;
}

export function GridControls({
  columns,
  density,
  layoutReady,
  onDensityChange,
  onResetLayout,
  onToggleColumn,
}: GridControlsProps) {
  const [columnMenuAnchor, setColumnMenuAnchor] = useState<HTMLElement | null>(null);
  const columnMenuOpen = columnMenuAnchor !== null;

  function openColumnMenu(event: MouseEvent<HTMLButtonElement>) {
    setColumnMenuAnchor(event.currentTarget);
  }

  function closeColumnMenu() {
    setColumnMenuAnchor(null);
  }

  function changeDensity(_event: MouseEvent<HTMLElement>, value: GridDensity | null) {
    if (value !== null) onDensityChange(value);
  }

  return (
    <div className="grid-controls" role="toolbar" aria-label="グリッド表示設定">
      <span className="grid-controls-label">表示</span>
      <ToggleButtonGroup
        exclusive
        size="small"
        value={density}
        aria-label="表示密度"
        onChange={changeDensity}
      >
        <ToggleButton value="standard" aria-label="標準表示">標準</ToggleButton>
        <ToggleButton value="compact" aria-label="コンパクト表示">コンパクト</ToggleButton>
      </ToggleButtonGroup>
      <Button
        aria-controls={columnMenuOpen ? "grid-column-menu" : undefined}
        aria-expanded={columnMenuOpen ? "true" : undefined}
        aria-haspopup="menu"
        size="small"
        variant="outlined"
        disabled={!layoutReady}
        onClick={openColumnMenu}
      >
        表示列
      </Button>
      <Menu
        id="grid-column-menu"
        anchorEl={columnMenuAnchor}
        open={columnMenuOpen}
        onClose={closeColumnMenu}
      >
        {columns.map((column) => (
          <MenuItem
            aria-checked={column.visible}
            dense
            key={column.colId}
            role="menuitemcheckbox"
            onClick={() => onToggleColumn(column.colId, !column.visible)}
          >
            <Checkbox checked={column.visible} disableRipple size="small" tabIndex={-1} />
            <span>{column.label}</span>
          </MenuItem>
        ))}
      </Menu>
      <Button disabled={!layoutReady} size="small" variant="text" onClick={onResetLayout}>
        列を初期化
      </Button>
    </div>
  );
}
