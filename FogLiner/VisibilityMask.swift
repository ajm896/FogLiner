//
//  VisibilityMask.swift
//  FogLiner
//
//  Created by Albert Morris on 6/29/26.
//

/// Per-cell visibility state. Keep occluded/outOfRange distinct in the model;
/// collapse to clear-vs-fog only at render time.
enum CellState: Equatable {
    case visible
    case occluded
    case outOfRange
}

/// Row-major 2D grid of CellState, indexed [row][col].
struct VisibilityMask {
    let cols: Int
    let rows: Int
    private var cells: [CellState]

    init(cols: Int, rows: Int, initialState: CellState = .outOfRange) {
        self.cols = cols
        self.rows = rows
        self.cells = [CellState](repeating: initialState, count: cols * rows)
    }

    subscript(row: Int, col: Int) -> CellState {
        get { cells[row * cols + col] }
        set { cells[row * cols + col] = newValue }
    }
}
