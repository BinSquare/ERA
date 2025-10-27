/**
 * ERA Animation - Conway's Game of Life visualization
 * 
 * Configuration constants (adjustable in constructor, lines 54-59):
 * - baselineLightness: 0.8 (20% gray baseline for ERA letters, 0=black, 1=white)
 * - maxAliveCells: 5000 (maximum living cells before cleanup, prevents performance issues)
 */

// Letter patterns (E R A) - each letter is a grid of 1s and 0s
export const LETTER_E = [
    [1,1,1,1,1],
    [1,0,0,0,0],
    [1,0,0,0,0],
    [1,1,1,1,0],
    [1,0,0,0,0],
    [1,0,0,0,0],
    [1,1,1,1,1]
];

export const LETTER_R = [
    [1,1,1,1,0],
    [1,0,0,0,1],
    [1,0,0,0,1],
    [1,1,1,1,0],
    [1,0,0,1,0],
    [1,0,0,0,1],
    [1,0,0,0,1]
];

export const LETTER_A = [
    [0,1,1,1,0],
    [1,0,0,0,1],
    [1,0,0,0,1],
    [1,1,1,1,1],
    [1,0,0,0,1],
    [1,0,0,0,1],
    [1,0,0,0,1]
];

// Conway's Game of Life with target pattern
export class ERAAnimation {
    constructor(canvas, ctx) {
        this.canvas = canvas;
        this.ctx = ctx;
        this.cellSize = 3; // Slightly larger cells for better visibility
        this.cols = Math.floor(canvas.width / this.cellSize);
        this.rows = Math.floor(canvas.height / this.cellSize);
        this.gridSize = 20; // Larger background grid for sparser look
        this.offsetX = (canvas.width % this.gridSize) / 2;
        this.offsetY = (canvas.height % this.gridSize) / 2;
        this.grid = [];
        this.nextGrid = [];
        this.targetGrid = [];
        this.targetDarkness = [];
        this.frame = 0;
        this.updateInterval = 3; // Conway update frequency
        this.spawnInterval = 20; // Spawn new patterns every 20 frames (more frequent)
        this.fadeInterval = 1; // Fade darkness every frame
        this.fadeAmount = 0.002; // Moderate fade rate (between 0.001 and 0.003)
        this.attractionStrength = 0.0;
        
        // Baseline lightness for ERA letters (0 = black, 1 = white)
        // 0.8 = 20% gray (80% lightness), adjust this value to change starting gray
        this.baselineLightness = 0.93;
        
        // Maximum number of alive cells allowed (prevents memory/performance issues)
        this.maxAliveCells = 5000;
        
        this.initializeGrids();
        this.setupTargetPattern();
        this.seedConwayPatterns();
        this.setupClickHandler();
    }
    
    initializeGrids() {
        for (let i = 0; i < this.rows; i++) {
            this.grid[i] = [];
            this.nextGrid[i] = [];
            this.targetGrid[i] = [];
            this.targetDarkness[i] = [];
            for (let j = 0; j < this.cols; j++) {
                this.grid[i][j] = 0;
                this.nextGrid[i][j] = 0;
                this.targetGrid[i][j] = 0;
                // Initialize ERA letter cells with baseline darkness (1 - baselineLightness)
                this.targetDarkness[i][j] = 0;
            }
        }
    }
    
    setupTargetPattern() {
        const centerCol = Math.floor(this.cols / 2);
        const centerRow = Math.floor(this.rows / 2);
        const scale = 4; // Slightly larger text
        const letterWidth = 5 * scale;
        const letterHeight = 7 * scale;
        const spacing = 2 * scale;
        const totalWidth = (letterWidth * 3) + (spacing * 2);
        const startCol = centerCol - Math.floor(totalWidth / 2);
        const startRow = centerRow - Math.floor(letterHeight / 2);
        
        this.addLetterToTarget(LETTER_E, startCol, startRow, scale);
        this.addLetterToTarget(LETTER_R, startCol + letterWidth + spacing, startRow, scale);
        this.addLetterToTarget(LETTER_A, startCol + (letterWidth + spacing) * 2, startRow, scale);
        
        // Initialize all ERA letter cells with baseline darkness
        const baselineDarkness = 1 - this.baselineLightness;
        for (let i = 0; i < this.rows; i++) {
            for (let j = 0; j < this.cols; j++) {
                if (this.targetGrid[i][j] === 1) {
                    this.targetDarkness[i][j] = baselineDarkness;
                }
            }
        }
    }
    
    addLetterToTarget(letter, startCol, startRow, scale = 1) {
        for (let row = 0; row < letter.length; row++) {
            for (let col = 0; col < letter[row].length; col++) {
                if (letter[row][col] === 1) {
                    for (let sy = 0; sy < scale; sy++) {
                        for (let sx = 0; sx < scale; sx++) {
                            const gridRow = startRow + (row * scale) + sy;
                            const gridCol = startCol + (col * scale) + sx;
                            if (gridRow >= 0 && gridRow < this.rows && gridCol >= 0 && gridCol < this.cols) {
                                this.targetGrid[gridRow][gridCol] = 1;
                            }
                        }
                    }
                }
            }
        }
    }
    
    getConwayPatterns() {
        return {
            glider: [[0,1,0], [0,0,1], [1,1,1]],
            gliderGun: [
                [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0],
                [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,0,0,0,0,0,0,0,0,0,0],
                [0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,1,1],
                [0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,1,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,1,1],
                [1,1,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
                [1,1,0,0,0,0,0,0,0,0,1,0,0,0,1,0,1,1,0,0,0,0,1,0,1,0,0,0,0,0,0,0,0,0,0,0],
                [0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0],
                [0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
                [0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
            ],
            lwss: [
                [0,1,0,0,1],
                [1,0,0,0,0],
                [1,0,0,0,1],
                [1,1,1,1,0]
            ],
            pulsar: [
                [0,0,1,1,1,0,0,0,1,1,1,0,0],
                [0,0,0,0,0,0,0,0,0,0,0,0,0],
                [1,0,0,0,0,1,0,1,0,0,0,0,1],
                [1,0,0,0,0,1,0,1,0,0,0,0,1],
                [1,0,0,0,0,1,0,1,0,0,0,0,1],
                [0,0,1,1,1,0,0,0,1,1,1,0,0],
                [0,0,0,0,0,0,0,0,0,0,0,0,0],
                [0,0,1,1,1,0,0,0,1,1,1,0,0],
                [1,0,0,0,0,1,0,1,0,0,0,0,1],
                [1,0,0,0,0,1,0,1,0,0,0,0,1],
                [1,0,0,0,0,1,0,1,0,0,0,0,1],
                [0,0,0,0,0,0,0,0,0,0,0,0,0],
                [0,0,1,1,1,0,0,0,1,1,1,0,0]
            ],
            // R-pentomino (creates chaos and spreads)
            rpentomino: [
                [0,1,1],
                [1,1,0],
                [0,1,0]
            ],
            // Blinker (simple oscillator)
            blinker: [
                [1,1,1]
            ],
            // Toad (oscillator)
            toad: [
                [0,1,1,1],
                [1,1,1,0]
            ],
            // Beacon (oscillator)
            beacon: [
                [1,1,0,0],
                [1,1,0,0],
                [0,0,1,1],
                [0,0,1,1]
            ],
            // Acorn (long-lived methuselah)
            acorn: [
                [0,1,0,0,0,0,0],
                [0,0,0,1,0,0,0],
                [1,1,0,0,1,1,1]
            ]
        };
    }
    
    seedConwayPatterns() {
        const patterns = this.getConwayPatterns();
        
        // Find all target cells (ERA letters) and place some patterns directly on them
        const targetCells = [];
        for (let i = 0; i < this.rows; i++) {
            for (let j = 0; j < this.cols; j++) {
                if (this.targetGrid[i][j] === 1) {
                    targetCells.push({ row: i, col: j });
                }
            }
        }
        
        if (targetCells.length === 0) return;
        
        // Helper function to get asymptotic distance (heavily biased toward closer spawns)
        const getAsymptoticDistance = (maxDist) => {
            // Use exponential distribution for asymptotic falloff
            // Most spawns will be very close (0-3 cells), fewer at max distance
            const rand = Math.random();
            return Math.floor(-Math.log(1 - rand * 0.95) * maxDist / 3);
        };
        
        // Place gliders very close to ERA letters
        for (let i = 0; i < 100; i++) {
            const cell = targetCells[Math.floor(Math.random() * targetCells.length)];
            const dist = getAsymptoticDistance(10);
            const angle = Math.random() * Math.PI * 2;
            const row = cell.row + Math.floor(Math.sin(angle) * dist);
            const col = cell.col + Math.floor(Math.cos(angle) * dist);
            
            if (row >= 0 && row < this.rows && col >= 0 && col < this.cols) {
                this.placePattern(patterns.glider, row, col);
            }
        }
        
        // More lightweight spaceships, very close to ERA
        for (let i = 0; i < 40; i++) {
            const cell = targetCells[Math.floor(Math.random() * targetCells.length)];
            const dist = getAsymptoticDistance(8);
            const angle = Math.random() * Math.PI * 2;
            const row = cell.row + Math.floor(Math.sin(angle) * dist);
            const col = cell.col + Math.floor(Math.cos(angle) * dist);
            
            if (row >= 0 && row < this.rows && col >= 0 && col < this.cols) {
                this.placePattern(patterns.lwss, row, col);
            }
        }
        
        // Pulsars very close to ERA
        for (let i = 0; i < 30; i++) {
            const cell = targetCells[Math.floor(Math.random() * targetCells.length)];
            const dist = getAsymptoticDistance(7);
            const angle = Math.random() * Math.PI * 2;
            const row = cell.row + Math.floor(Math.sin(angle) * dist);
            const col = cell.col + Math.floor(Math.cos(angle) * dist);
            
            if (row >= 0 && row < this.rows && col >= 0 && col < this.cols) {
                this.placePattern(patterns.pulsar, row, col);
            }
        }
        
        // R-pentominos for chaos, very close to ERA
        for (let i = 0; i < 20; i++) {
            const cell = targetCells[Math.floor(Math.random() * targetCells.length)];
            const dist = getAsymptoticDistance(6);
            const angle = Math.random() * Math.PI * 2;
            const row = cell.row + Math.floor(Math.sin(angle) * dist);
            const col = cell.col + Math.floor(Math.cos(angle) * dist);
            
            if (row >= 0 && row < this.rows && col >= 0 && col < this.cols) {
                this.placePattern(patterns.rpentomino, row, col);
            }
        }
        
        // Fewer glider guns, but still close to ERA (max 10 cells)
        for (let i = 0; i < 10; i++) {
            const cell = targetCells[Math.floor(Math.random() * targetCells.length)];
            const dist = getAsymptoticDistance(10);
            const angle = Math.random() * Math.PI * 2;
            const row = cell.row + Math.floor(Math.sin(angle) * dist);
            const col = cell.col + Math.floor(Math.cos(angle) * dist);
            
            if (row >= 0 && row < this.rows && col >= 0 && col < this.cols) {
                this.placePattern(patterns.gliderGun, row, col);
            }
        }
    }
    
    setupClickHandler() {
        const self = this;
        let lastSpawnTime = 0;
        let lastSpawnRow = -100;
        let lastSpawnCol = -100;
        const spawnDelay = 30; // Faster spawning (was 50ms)
        const minDistance = 5; // Closer spawning allowed (was 8)
        
        this.canvas.addEventListener('mousemove', function(event) {
            const currentTime = Date.now();
            if (currentTime - lastSpawnTime < spawnDelay) return;
            
            const rect = self.canvas.getBoundingClientRect();
            const x = event.clientX - rect.left;
            const y = event.clientY - rect.top;
            
            // Convert pixel coordinates to grid coordinates
            const col = Math.floor((x - self.offsetX) / self.cellSize);
            const row = Math.floor((y - self.offsetY) / self.cellSize);
            
            // Check if too close to last spawn
            const distance = Math.sqrt(Math.pow(row - lastSpawnRow, 2) + Math.pow(col - lastSpawnCol, 2));
            if (distance < minDistance) return;
            
            lastSpawnTime = currentTime;
            lastSpawnRow = row;
            lastSpawnCol = col;
            
            const patterns = self.getConwayPatterns();
            const patternTypes = ['glider', 'lwss', 'rpentomino', 'blinker', 'toad', 'acorn'];
            
            // Spawn 2-3 patterns in a small cluster around mouse
            const spawnCount = 2 + Math.floor(Math.random() * 2);
            for (let i = 0; i < spawnCount; i++) {
                // Offset each pattern slightly from center
                const offsetRow = row + Math.floor(Math.random() * 10 - 5);
                const offsetCol = col + Math.floor(Math.random() * 10 - 5);
                
                if (offsetRow >= 0 && offsetRow < self.rows && offsetCol >= 0 && offsetCol < self.cols) {
                    // Clear a small area before placing to prevent block formation
                    self.clearArea(offsetRow, offsetCol, 2);
                    
                    const randomPattern = patternTypes[Math.floor(Math.random() * patternTypes.length)];
                    self.placePattern(patterns[randomPattern], offsetRow, offsetCol);
                }
            }
        });
        
        // Keep click functionality too
        this.canvas.addEventListener('click', function(event) {
            const rect = self.canvas.getBoundingClientRect();
            const x = event.clientX - rect.left;
            const y = event.clientY - rect.top;
            
            const col = Math.floor((x - self.offsetX) / self.cellSize);
            const row = Math.floor((y - self.offsetY) / self.cellSize);
            
            // Clear area before placing
            self.clearArea(row, col, 4);
            
            const patterns = self.getConwayPatterns();
            const patternTypes = ['glider', 'lwss', 'rpentomino', 'blinker', 'toad', 'acorn'];
            const randomPattern = patternTypes[Math.floor(Math.random() * patternTypes.length)];
            
            self.placePattern(patterns[randomPattern], row, col);
        });
    }
    
    clearArea(centerRow, centerCol, radius) {
        for (let i = -radius; i <= radius; i++) {
            for (let j = -radius; j <= radius; j++) {
                const row = centerRow + i;
                const col = centerCol + j;
                if (row >= 0 && row < this.rows && col >= 0 && col < this.cols) {
                    this.grid[row][col] = 0;
                }
            }
        }
    }
    
    placePattern(pattern, startRow, startCol) {
        for (let i = 0; i < pattern.length; i++) {
            for (let j = 0; j < pattern[i].length; j++) {
                const row = startRow + i;
                const col = startCol + j;
                if (row >= 0 && row < this.rows && col >= 0 && col < this.cols) {
                    this.grid[row][col] = pattern[i][j];
                }
            }
        }
    }
    
    countNeighbors(row, col) {
        let count = 0;
        for (let i = -1; i <= 1; i++) {
            for (let j = -1; j <= 1; j++) {
                if (i === 0 && j === 0) continue;
                const newRow = row + i;
                const newCol = col + j;
                if (newRow >= 0 && newRow < this.rows && newCol >= 0 && newCol < this.cols) {
                    count += this.grid[newRow][newCol];
                }
            }
        }
        return count;
    }
    
    getAliveCellCount() {
        let count = 0;
        for (let i = 0; i < this.rows; i++) {
            for (let j = 0; j < this.cols; j++) {
                if (this.grid[i][j] === 1) {
                    count++;
                }
            }
        }
        return count;
    }
    
    enforceCellLimit() {
        // Count current alive cells
        let aliveCount = 0;
        const aliveCells = [];
        
        for (let i = 0; i < this.rows; i++) {
            for (let j = 0; j < this.cols; j++) {
                if (this.grid[i][j] === 1) {
                    aliveCount++;
                    aliveCells.push({ row: i, col: j });
                }
            }
        }
        
        // If over limit, randomly remove cells until within limit
        if (aliveCount > this.maxAliveCells) {
            const excessCells = aliveCount - this.maxAliveCells;
            
            // Shuffle alive cells array to remove random ones
            for (let i = aliveCells.length - 1; i > 0; i--) {
                const j = Math.floor(Math.random() * (i + 1));
                const temp = aliveCells[i];
                aliveCells[i] = aliveCells[j];
                aliveCells[j] = temp;
            }
            
            // Remove excess cells (from shuffled list)
            for (let i = 0; i < excessCells; i++) {
                const cell = aliveCells[i];
                this.grid[cell.row][cell.col] = 0;
            }
        }
    }
    
    spawnRandomPattern() {
        // Get target cells (ERA letters)
        const targetCells = [];
        for (let i = 0; i < this.rows; i++) {
            for (let j = 0; j < this.cols; j++) {
                if (this.targetGrid[i][j] === 1) {
                    targetCells.push({ row: i, col: j });
                }
            }
        }
        
        if (targetCells.length === 0) return;
        
        const patterns = this.getConwayPatterns();
        const patternTypes = ['glider', 'lwss', 'rpentomino', 'blinker', 'toad', 'acorn'];
        const randomPattern = patternTypes[Math.floor(Math.random() * patternTypes.length)];
        
        // Pick a random ERA cell as the center point
        const centerCell = targetCells[Math.floor(Math.random() * targetCells.length)];
        
        // Use asymptotic distribution: heavily biased toward very close spawns (0-10 cells max)
        // 60% chance: 0-3 cells, 30% chance: 3-7 cells, 10% chance: 7-10 cells
        const rand = Math.random();
        let distance, row, col;
        
        if (rand < 0.6) {
            // 60% chance: Very close (0-3 cells) with exponential falloff
            distance = Math.floor(-Math.log(1 - Math.random() * 0.95) * 1);
            const angle = Math.random() * Math.PI * 2;
            row = centerCell.row + Math.floor(Math.sin(angle) * distance);
            col = centerCell.col + Math.floor(Math.cos(angle) * distance);
        } else if (rand < 0.9) {
            // 30% chance: Close (3-7 cells)
            distance = 3 + Math.floor(-Math.log(1 - Math.random() * 0.9) * 1.5);
            const angle = Math.random() * Math.PI * 2;
            row = centerCell.row + Math.floor(Math.sin(angle) * distance);
            col = centerCell.col + Math.floor(Math.cos(angle) * distance);
        } else {
            // 10% chance: Medium close (7-10 cells)
            distance = 7 + Math.floor(Math.random() * 3);
            const angle = Math.random() * Math.PI * 2;
            row = centerCell.row + Math.floor(Math.sin(angle) * distance);
            col = centerCell.col + Math.floor(Math.cos(angle) * distance);
        }
        
        if (row >= 0 && row < this.rows && col >= 0 && col < this.cols) {
            this.placePattern(patterns[randomPattern], row, col);
        }
    }
    
    update() {
        this.frame++;
        
        // Enforce cell population limit periodically (every 30 frames for performance)
        if (this.frame % 30 === 0) {
            this.enforceCellLimit();
        }
        
        // Fade darkness every frame back to baseline
        const baselineDarkness = 1 - this.baselineLightness;
        if (this.frame % this.fadeInterval === 0) {
            for (let i = 0; i < this.rows; i++) {
                for (let j = 0; j < this.cols; j++) {
                    // Only fade if on a target cell (ERA letter)
                    if (this.targetGrid[i][j] === 1 && this.targetDarkness[i][j] > baselineDarkness) {
                        this.targetDarkness[i][j] = Math.max(baselineDarkness, this.targetDarkness[i][j] - this.fadeAmount);
                    }
                }
            }
        }
        
        // Spawn new patterns periodically (but check limit first)
        if (this.frame % this.spawnInterval === 0) {
            // Quick check: only spawn if we're not too close to limit
            const currentAliveCount = this.getAliveCellCount();
            if (currentAliveCount < this.maxAliveCells * 0.9) {
                // Spawn 4-6 patterns at once (more activity)
                const spawnCount = 4 + Math.floor(Math.random() * 3);
                for (let i = 0; i < spawnCount; i++) {
                    this.spawnRandomPattern();
                }
            }
        }
        
        // Only update Conway's rules every N frames
        if (this.frame % this.updateInterval !== 0) return;
        
        // Apply Conway's Game of Life rules (pure, no attraction)
        for (let i = 0; i < this.rows; i++) {
            for (let j = 0; j < this.cols; j++) {
                const neighbors = this.countNeighbors(i, j);
                const currentState = this.grid[i][j];
                const targetState = this.targetGrid[i][j];
                
                // Standard Conway rules
                if (currentState === 1) {
                    // Cell is alive - increase darkness if on target with diminishing returns
                    if (targetState === 1) {
                        // Use exponential decay: add more when light, less when already dark
                        // Formula: add = baseAmount * (1 - currentDarkness)
                        const currentDarkness = this.targetDarkness[i][j];
                        const addAmount = 0.08 * (1 - currentDarkness);
                        this.targetDarkness[i][j] = Math.min(1, currentDarkness + addAmount);
                    }
                    
                    if (neighbors < 2 || neighbors > 3) {
                        this.nextGrid[i][j] = 0;
                    } else {
                        this.nextGrid[i][j] = 1;
                    }
                } else {
                    // Cell is dead
                    if (neighbors === 3) {
                        this.nextGrid[i][j] = 1;
                    } else {
                        this.nextGrid[i][j] = 0;
                    }
                }
            }
        }
        
        // Swap grids
        const temp = this.grid;
        this.grid = this.nextGrid;
        this.nextGrid = temp;
    }
    
    drawBackground() {
        // Draw target letters with progressive darkness from baseline
        const baselineDarkness = 1 - this.baselineLightness;
        
        for (let i = 0; i < this.rows; i++) {
            for (let j = 0; j < this.cols; j++) {
                if (this.targetGrid[i][j] === 1) {
                    // Get darkness value, ensuring minimum of baseline
                    const darkness = Math.max(baselineDarkness, this.targetDarkness[i][j]);
                    
                    // Map darkness to gray level: baselineLightness (e.g. 0.8) to 0 (black)
                    // baselineDarkness (e.g. 0.2) maps to 204 gray (20% gray)
                    // 1.0 darkness maps to 0 gray (pure black)
                    const maxGray = 255 * this.baselineLightness;
                    const grayLevel = Math.floor(maxGray * (1 - darkness));
                    
                    // Opacity from baseline to full
                    const baseOpacity = 0.5; // Make baseline visible
                    const opacity = baseOpacity + (darkness * (1 - baseOpacity));
                    
                    this.ctx.fillStyle = 'rgba(' + grayLevel + ', ' + grayLevel + ', ' + grayLevel + ', ' + opacity + ')';
                    this.ctx.fillRect(
                        j * this.cellSize + this.offsetX,
                        i * this.cellSize + this.offsetY,
                        this.cellSize,
                        this.cellSize
                    );
                }
            }
        }
    }
    
    draw() {
        // Draw background with progressive darkness first
        this.drawBackground();
        
        // Draw living cells
        for (let i = 0; i < this.rows; i++) {
            for (let j = 0; j < this.cols; j++) {
                if (this.grid[i][j] === 1) {
                    // Lighter gray cells
                    this.ctx.fillStyle = 'rgba(180, 180, 180, 0.4)';
                    this.ctx.fillRect(
                        j * this.cellSize + this.offsetX,
                        i * this.cellSize + this.offsetY,
                        this.cellSize,
                        this.cellSize
                    );
                }
            }
        }
    }
}

// Setup canvas and dimensions
export function getBrowserWindowSize() {
    const win = window;
    const doc = document;
    const offset = 20;
    const docElem = doc.documentElement;
    const body = doc.getElementsByTagName('body')[0];
    const browserWindowWidth = win.innerWidth || docElem.clientWidth || body.clientWidth;
    const browserWindowHeight = win.innerHeight || docElem.clientHeight || body.clientHeight;
    return { x: browserWindowWidth - offset, y: browserWindowHeight - offset };
}

// Generate textured grid background
export function generateTexturedGrid(SCREEN_WIDTH, SCREEN_HEIGHT) {
    const gridCanvas = document.getElementById('gridBackground');
    const gridCtx = gridCanvas.getContext('2d');
    
    gridCanvas.width = SCREEN_WIDTH;
    gridCanvas.height = SCREEN_HEIGHT;
    
    const baseSize = 20; // Larger grid size for sparser look
    const occupied = new Set();
    
    // Helper to check if area is occupied
    function isOccupied(x, y, w, h) {
        for (let i = y; i < y + h; i += baseSize) {
            for (let j = x; j < x + w; j += baseSize) {
                if (occupied.has(j + ',' + i)) return true;
            }
        }
        return false;
    }
    
    // Helper to mark area as occupied
    function markOccupied(x, y, w, h) {
        for (let i = y; i < y + h; i += baseSize) {
            for (let j = x; j < x + w; j += baseSize) {
                occupied.add(j + ',' + i);
            }
        }
    }
    
    // Draw rectangles with varied sizes
    for (let y = 0; y < SCREEN_HEIGHT; y += baseSize) {
        for (let x = 0; x < SCREEN_WIDTH; x += baseSize) {
            if (isOccupied(x, y, baseSize, baseSize)) continue;
            
            // Randomly choose size variations
            const rand = Math.random();
            let width = baseSize;
            let height = baseSize;
            
            if (rand < 0.15 && !isOccupied(x, y, baseSize * 4, baseSize * 4)) {
                // 4x4 square (rare)
                width = baseSize * 4;
                height = baseSize * 4;
            } else if (rand < 0.25 && !isOccupied(x, y, baseSize * 2, baseSize * 4)) {
                // 2x4 rectangle
                width = baseSize * 2;
                height = baseSize * 4;
            } else if (rand < 0.35 && !isOccupied(x, y, baseSize * 4, baseSize * 2)) {
                // 4x2 rectangle
                width = baseSize * 4;
                height = baseSize * 2;
            } else if (rand < 0.5 && !isOccupied(x, y, baseSize * 2, baseSize * 2)) {
                // 2x2 square
                width = baseSize * 2;
                height = baseSize * 2;
            } else if (rand < 0.6 && !isOccupied(x, y, baseSize * 3, baseSize)) {
                // 3x1 rectangle
                width = baseSize * 3;
                height = baseSize;
            } else if (rand < 0.7 && !isOccupied(x, y, baseSize, baseSize * 3)) {
                // 1x3 rectangle
                width = baseSize;
                height = baseSize * 3;
            }
            // else: 1x1 (default)
            
            markOccupied(x, y, width, height);
            
            // Draw the rectangle outline
            gridCtx.strokeStyle = 'rgba(128, 128, 128, 0.15)';
            gridCtx.lineWidth = 1;
            gridCtx.strokeRect(x, y, width, height);
        }
    }
}

export function updateCanvas(ctx, SCREEN_WIDTH, SCREEN_HEIGHT) {
    ctx.clearRect(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT);
    ctx.fillStyle = 'white';
    ctx.fillRect(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT);
}

export function initERAAnimation() {
    const c = document.getElementById("gridwormCanvas");
    const ctx = c.getContext("2d");
    
    // Get the canvas container's actual dimensions
    const canvasContainer = c.parentElement;
    const containerWidth = canvasContainer.clientWidth;
    const containerHeight = canvasContainer.clientHeight;
    
    c.width = containerWidth;
    c.height = containerHeight;
    
    let SCREEN_WIDTH = containerWidth;
    let SCREEN_HEIGHT = containerHeight;
    
    let eraAnimation;
    
    function onWindowResize() {
        // Use canvas container dimensions
        const containerWidth = canvasContainer.clientWidth;
        const containerHeight = canvasContainer.clientHeight;
        
        c.width = containerWidth;
        c.height = containerHeight;
        SCREEN_WIDTH = containerWidth;
        SCREEN_HEIGHT = containerHeight;
        
        // Regenerate grid and ERA animation on resize
        generateTexturedGrid(SCREEN_WIDTH, SCREEN_HEIGHT);
        eraAnimation = new ERAAnimation(c, ctx);
    }
    
    window.addEventListener('resize', onWindowResize);
    
    generateTexturedGrid(SCREEN_WIDTH, SCREEN_HEIGHT);
    
    eraAnimation = new ERAAnimation(c, ctx);
    
    function doAnimationLoop(timestamp) {
        updateCanvas(ctx, SCREEN_WIDTH, SCREEN_HEIGHT);
        
        // Draw ERA animation
        eraAnimation.update();
        eraAnimation.draw();
        
        requestAnimationFrame(doAnimationLoop);
    }
    
    requestAnimationFrame(doAnimationLoop);
}

