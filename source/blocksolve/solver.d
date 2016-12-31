module blocksolve.solver;
import blocksolve.datatypes;


bool any(T)(T[] ts) if (__traits(isArithmetic, T) || is(T == bool)) {
    foreach (t; ts) {
        if (t) return true;
    }
    return false;
}

bool all(T)(T[] ts) if (__traits(isArithmetic, T) || is(T == bool)) {
    foreach (t; ts) {
        if (t) return false;
    }
    return true;
}

// A push procedure for Stacks.
// Importantly, this can be used to push to a 'null' (empty) stack as well.
// That's why this isn't part of the class definition.
Stack!T push(T)(Stack!T stack, T t) {
    return new Stack!T(t, stack);
}

// A length function for Stacks.
// Similar reasoning to `push`, this uses null for the empty (length 0) stack.
// Of course, this runs in linear time unfortunately.
uint length(T)(Stack!T stack) {
    if (stack is null) return 0;
    else return 1 + stack.pop.length;
}

// returns all BlockGroups present in the current state of `gb`
BlockGroup[] findGroups(in GameBoard gb) {

    BlockGroup[] foundGroups;       // all groups we've found so far
    Shape checkedCoords; // places in the gameboard which are already parts of groups

    // iterate over starting positions in the game board
    foreach (i; 0..BOARDWIDTH) {
        foreach (j; 0..BOARDHEIGHT) {
            if (gb.existsGroupAt(Coord(i, j)) && !checkedCoords[i][j]) {
                
                // do a search in the board for the group
                BlockGroup theGroup = gb.getGroup(Coord(i, j));
                
                // iterate over the blockgroup's shape to set seen coordinates
                // (so we don't repeat ourselves)
                foreach (i2; 0..BOARDWIDTH)
                foreach (j2; 0..BOARDHEIGHT)
                if (theGroup.shape[i2][j2])
                    checkedCoords[i2][j2] = true;
                
                // add the blockgroup to our list
                foundGroups ~= theGroup;
            }
        }
    }

    return foundGroups;
}

// does a search to construct a BlockGroup starting at the location specified
BlockGroup getGroup(in GameBoard gb, in Coord coord) {

    // coordinates we've already visited in the board.
    // this will also represent the blockgroup's shape in the end.
    Shape visitedCoords;

    // the kind of block we're going to be looking for
    Block blockGroupType = gb.blocks[coord.x][coord.y];

    // and a counter to store their total
    int groupSize;

    // do a depth-first search for all similar blocks in the region.
    void search(in Coord loc) {
        // make sure we're in the region
        if (!(loc.x >= 0 && loc.x < BOARDWIDTH)) return;
        if (!(loc.y >= 0 && loc.y < BOARDHEIGHT)) return;
        // and on a block of the right type
        if (gb.blocks[loc.x][loc.y] != blockGroupType) return;
        // and haven't been here before
        if (visitedCoords[loc.x][loc.y]) return;

        // then, register that we've seen this location before
        visitedCoords[loc.x][loc.y] = true;
        // and update our total to reflect that
        groupSize++;

        // then do a recursive check on the neighboring squares.
        search(Coord(loc.x - 1, loc.y));
        search(Coord(loc.x + 1, loc.y));
        search(Coord(loc.x, loc.y + 1));
        search(Coord(loc.x, loc.y - 1));
    }

    search(coord);

    // then we can construct a blockGroup given that info
    return BlockGroup(groupSize, blockGroupType, visitedCoords);
}

// tests whether a BlockGroup could be found at the location specified
bool existsGroupAt(in GameBoard gb, in Coord loc)
in {
    assert(loc.x < BOARDWIDTH);
    assert(loc.y < BOARDHEIGHT);
}
body {
    
    Block blockType = gb.blocks[loc.x][loc.y];
    // if the blockType is 0, it's an empty square, so no group is here.
    if (!blockType) return false;

    // then just check the surrounding locations for equality
    if (loc.x > 0 && 
        gb.blocks[loc.x - 1][loc.y] == blockType) return true;
    if (loc.x + 1 < BOARDWIDTH &&
        gb.blocks[loc.x + 1][loc.y] == blockType) return true;
    if (loc.y > 0 &&
        gb.blocks[loc.x][loc.y - 1] == blockType) return true;
    if (loc.y + 1 < BOARDHEIGHT &&
        gb.blocks[loc.x][loc.y + 1] == blockType) return true;
    return false;
}

// compacts the gameboard as the mechanics allow.
// i.e. gravity is applied to blocks and then columns replace empty ones to their left.
GameBoard applyPhysics(in GameBoard gb) {

    Block[BOARDHEIGHT][BOARDWIDTH] newBoard;

    uint i = 0;
    foreach (col; gb.blocks) {
        if (col == Block[BOARDHEIGHT].init) continue; // skip if the column is empty (to collapse the columns and ignore trailing empty ones)
        uint j = 0;
        foreach (block; col) {
            if (block == 0) continue; // skip zeros (effectively collapsing blocks)
            newBoard[i][j++] = block;
        }
        i++;
    }

    return GameBoard(newBoard);
}

// zeroes out elements of `gb` which are within the shape of `bg`
GameBoard removeGroup(GameBoard gb, in BlockGroup bg) {

    foreach (i; 0..BOARDWIDTH) {
        foreach (j; 0..BOARDHEIGHT) {
            if (bg.shape[i][j]) {
                gb.blocks[i][j] = 0;
            }
        }
    }

    return gb;

}

// creates a mapping from each block type to the number of that kind of blocks on the board
int[Block] getBlockTotals(in GameBoard gb) {
    int[Block] mapping;

    foreach (i; 0..BOARDWIDTH) {
        foreach (j; 0..BOARDHEIGHT) {
            if (gb.blocks[i][j] == 0) continue;
            mapping[gb.blocks[i][j]]++;
        }
    }

    return mapping;
}


synchronized interface SolutionFinder {
    void solve(GameBoard gb);
}

synchronized class DefaultSolutionFinder : SolutionFinder {
    private SolutionHandler handler;
    private MovePrioritizer prioritizer;

    this(shared SolutionHandler handler, shared MovePrioritizer prioritizer) {
        this.handler = handler;
        this.prioritizer = prioritizer;
    }

    void solve(GameBoard gb) {
        solve(gb, EmptyMoveSequence);
    }

    void solve(GameBoard gb, MoveSequence movesSoFar) {
        import std.stdio: writeln;
        // if the gameboard is empty, we've done it!
        if (gb.isEmpty) {
            // handle it properly
            handler.handle(movesSoFar);
            // then end our work.
            return;
        }

        // if the board has any loner blocks, we're stupid and shouldn't keep going
        foreach (total; gb.getBlockTotals) {
            // if there's one left, we obviously can't win.
            // so, we just abort in that case, after notifying of a dead end.
            if (total == 1) {
                handler.handleDead(movesSoFar);
                return;
            }
        }

        // we'll go ahead and find the next possible moves.
        BlockGroup[] nextMoves = gb.findGroups;

        // now, do a depth-first search of moves in priority order
        foreach (move; prioritizer.prioritize(nextMoves)) {
            // try the move to see if we win
            solve(gb.removeGroup(move).applyPhysics, movesSoFar.push(move));
            // otherwise we'll just try the next choice.
        }

        // nothing else for us to do now.

    }

}

synchronized class ParallelSolutionFinder : SolutionFinder {
    private SolutionHandler handler;
    private MovePrioritizer prioritizer;

    this(shared SolutionHandler handler, shared MovePrioritizer prioritizer) {
        this.handler = handler;
        this.prioritizer = prioritizer;
    }

    void solve(GameBoard gb) {
        solve(gb, EmptyMoveSequence);
    }

    void solve(GameBoard gb, MoveSequence movesSoFar = EmptyMoveSequence) {
        import std.parallelism: parallel;
        
        // if the gameboard is empty, we've done it!
        if (gb.isEmpty) {
            // handle it properly
            handler.handle(movesSoFar);
            // then end our work.
            return;
        }

        // if the board has any loner blocks, we're stupid and shouldn't keep going
        foreach (total; gb.getBlockTotals) {
            // if there's one left, we obviously can't win.
            // so, we just abort in that case.
            if (total == 1) {
                handler.handleDead(movesSoFar);
                return;
            }
        }

        // we'll go ahead and find the next possible moves.
        BlockGroup[] nextMoves = gb.findGroups;

        // now, do a depth-first search of moves in priority order (in parallel!)
        // the method by which to parallelize here could be fooled around with to gain a bit more perhaps.
        foreach (move; prioritizer.prioritize(nextMoves).parallel) {
            // try the move to see if we win
            solve(gb.removeGroup(move).applyPhysics, movesSoFar.push(move));
            // otherwise we'll just try the next choice.
        }

        // nothing else for us to do now.
    }
}


// function for getting a game board from user input
GameBoard getInputGameBoard() {
    import std.stdio: writefln, readln;
    import std.format: format;
    
    ubyte identifier = 1; // keeps track of each unique character entered
    ubyte[dchar] idmap; // keeps track of which ID each character entered should have
    GameBoard gb; // the gameboard we're going to be modifying
    
    writefln("Enter %d lines of %d characters representing the state of the board.", BOARDHEIGHT, BOARDWIDTH);
    string line;
    foreach (j; 0..BOARDHEIGHT) {
        // get a line of proper length
        do {
            line = readln;
            if (line.length < BOARDWIDTH) {
                writefln("Line must be at least %d. Enter a new line:", BOARDWIDTH);
            }
        } while (line.length < BOARDWIDTH);

        foreach (i; 0..BOARDWIDTH) {
            if (line[i] !in idmap)
                idmap[line[i]] = identifier++;
            //writefln("%d", i);
            gb.blocks[i][BOARDHEIGHT - j - 1] = idmap[line[i]];
        }
    }

    return gb;
}

// function for reading a board from a string
GameBoard gameBoardFromString(string gbStr) {
    import std.string: splitLines;

    ubyte identifier = 1; // keeps track of each unique character entered
    ubyte[dchar] idmap; // keeps track of which ID each character entered should have
    GameBoard gb; // the gameboard we're going to be modifying
    
    string[] lines = gbStr.splitLines;
    string line;
    foreach (j; 0..BOARDHEIGHT) {
        // get a line of proper length
        line = lines[j];
        foreach (i; 0..BOARDWIDTH) {
            if (line[i] !in idmap)
                idmap[line[i]] = identifier++;
            //writefln("%d", i);
            gb.blocks[i][BOARDHEIGHT - j - 1] = idmap[line[i]];
        }
    }

    return gb;
    
}


// a really easy gameboard (3 colors)
immutable easyTestBoard = gameBoardFromString(
    "RYGGGYYYRR\nRRYGYRYYRR\nRYGRRRYGRR\nRYGRRYYGYG\nRGGGRYGGGG\nYGGGRRGYGG\nGYYYRRRGGG\nGYGGRRRYGR\nYYYGRYGYGR\nRRGRRRRGGR"
);

// the game board we're benchmarking right now (5 colors)
immutable benchTestBoard = gameBoardFromString(
    "pppyrppggg\nppprrybbgy\nbrrrbygbgb\nbggrgppgrg\nyyyrggpgrr\nppgrbpppyr\npprybpppyy\nbbybbrpprr\ngbyyrrpbyb\nggggrrrbbb"
);

// a game board which usually takes a long time to solve by brute force (6 colors)
immutable hardTestBoard = gameBoardFromString(
    "BYBRGTTGPP\nYYTTYTRTPG\nYYPGYTRRTG\nBYPGYRTPTG\nBBYYTPPGTP\nGTTTPPGRTT\nGBTPBPRBBP\nGBGBRTBYYY\nBBBBRRYYYY\nBTGTRRBBYP"
);




void solveWith(shared SolutionFinder fs, GameBoard gb) {
    fs.solve(gb);
}

void main() {

    auto timer      = new shared TimerSolutionHandler;
    auto print      = new shared PrintInstructionsHandler;
    auto score      = new shared ScoreHunterHandler(print, 3000, 300);

    auto defaultPri = new shared DoNothingPrioritizer;
    auto sizePri    = new shared BySizePrioritizer;
    auto reversePri = new shared ReversePrioritizer;
    auto sizerevPri = new shared ReversePrioritizer(new shared BySizePrioritizer);

    auto fs1 = new shared DefaultSolutionFinder(timer, defaultPri);
    auto fs2 = new shared DefaultSolutionFinder(timer, sizePri);
    auto fs3 = new shared DefaultSolutionFinder(timer, reversePri);
    auto fs4 = new shared DefaultSolutionFinder(timer, sizerevPri);
    GameBoard gb = benchTestBoard;

    import std.parallelism: taskPool, task;
    taskPool.isDaemon = false;
    taskPool.put(task!solveWith(fs1, gb));
    taskPool.put(task!solveWith(fs2, gb));
    taskPool.put(task!solveWith(fs3, gb));
    taskPool.put(task!solveWith(fs4, gb));

}