module blocksolve.datatypes;


// 
//  Basic data types and aliases
//


// Important constants which affect a LOT of the program
immutable BOARDWIDTH  = 10;
immutable BOARDHEIGHT = 10;

// Alias for the Block identifier type for now
// this could be upgraded to a struct or something if needed.
alias Block = ubyte;


// Pair type; could be useful for representing coordinates
struct Pair(T, U = T) {
    T fst;
    alias x = fst;
    U snd;
    alias y = snd;

    string toString() {
        import std.format: format;
        return format("(%s, %s)", fst, snd);
    }
}

// ... so we'll use it for coordinates too.
alias Coord = Pair!uint;


// The struct representing the state of the game itself.
// This contains info on the type of block at each position on the board.
struct GameBoard {
    // indexed with column-major order,
    // since this suits the game's mechanics better
    Block[BOARDHEIGHT][BOARDWIDTH] blocks;

    static immutable GameBoard Empty = GameBoard();

    string toString() const {
        import std.array: appender;
        import std.format: format;

        auto app = appender!string();
        foreach (j; 0..BOARDHEIGHT) {
            foreach (i; 0..BOARDWIDTH) {
                app.put(blocks[i][BOARDHEIGHT - j - 1] == 0 ? "." : format("%d", blocks[i][BOARDHEIGHT - j - 1]));
            }
            app.put('\n');
        }
        return app.data;
    }

    bool isEmpty() const @property {
        return this == GameBoard.Empty;
    }

}


// A convenience alias for this common structure
alias Shape = bool[BOARDHEIGHT][BOARDWIDTH];


// A struct representing a collection of similarly-colored blocks.
// It contains enough info to calculate scoring and the next board states.
struct BlockGroup {
    
    int   groupSize; // the number of blocks in the group
    Block blockType; // the type of block the group is of

    // The shape is useful for printing the group.
    // each boolean represents whether the square is occupied
    // by this group.
    Shape shape; 

    string toString() {
        import std.array: appender;

        auto app = appender!string();
        foreach (j; 0..BOARDHEIGHT) {
            foreach (i; 0..BOARDWIDTH) {
                app.put(shape[i][BOARDHEIGHT - j - 1] ? '#' : '.');
            }
            app.put('\n');
        }
        return app.data;
    }
}


// A singly-linked list which should be better for storing
// the tree structures which emerge in the recursive algorithm.
class Stack(T) {
    private T data;
    private Stack!T next = null;

    this(inout T data) inout {
        this.data = data;
    }

    this(inout shared T data) inout shared {
        this.data = data;
    }

    this(inout T data, inout Stack!T next) inout {
        this.data = data;
        this.next = next;
    }

    this(inout shared T data, inout shared Stack!T next) inout shared {
        this.data = data;
        this.next = next;
    }

    this(uint n)(T[n] ts...) if (n > 0) {
        this.data = ts[0];
        static if (n > 1) {
            this.next = new Stack!T(ts[1..$]);
        }
    }

    inout(T) top() inout @property {
        return data;
    }

    inout(shared(T)) top() inout @property shared {
        return data;
    }

    // This copy ability is important for use in parallel algorithms I think
    inout(Stack!T) copy() inout {
        return new inout Stack!T(data, next is null ? null : next.copy);
    }

    inout(shared(Stack!T)) copy() inout shared {
        return new inout shared Stack!T(data, next is null ? null : next.copy);
    }

    // Pop method (non-mutating)
    inout(Stack!T) pop() inout {
        return next;
    }

    inout(shared(Stack!T)) pop() inout shared {
        return next;
    }

    // method for getting an array (which is easier to iterate over)
    T[] toArray() {
        T[] ts;
        Stack!T current = this;
        while (current.pop !is null) {
            ts ~= current.top;
            current = current.pop;
        }
        return ts;
    }

    shared(T[]) toArray() shared {
        shared(T[]) ts;
        shared Stack!T current = this;
        while (current.pop !is null) {
            ts ~= current.top;
            current = current.pop;
        }
        return ts;
    }    

}

enum StandardMoveSequenceLength = 30;

struct PAStack(T, uint maxlen = StandardMoveSequenceLength) if (maxlen > 0) {
    T[maxlen] data;
    uint currentPos = 0;

    alias length = currentPos;

    shared(typeof(this)) asShared() const @property {
        return shared PAStack!(T, maxlen)(cast(shared)this.data, this.currentPos);
    }

    typeof(this) push(T t) const {
        assert(currentPos + 1 < maxlen, "PAStack max length exceeded.");
        T[maxlen] newData = data.dup;
        newData[currentPos] = t;
        return PAStack!(T, maxlen)(newData, currentPos + 1);
    }

    typeof(this) pop() const {
        return PAStack!(T, maxlen)(this.data, currentPos - 1);
    }
    
    T top() const @property {
        return this.data[0];
    }

    // opApply so that this can be used in foreach statements
    int opApply(int delegate(ref T) dg) {
        int result = 0;
        foreach (ref t; data[0..length]) {
            result = dg(t);
            if (result) break;
        }
        return result;
    }
    
}

// Convenience alias since this is mostly what we'll be using
//alias MoveSequence = Stack!BlockGroup;
//enum EmptyMoveSequence = null;
alias MoveSequence = PAStack!BlockGroup;
enum EmptyMoveSequence = PAStack!BlockGroup();


//
//  Handlers for polymorphic solution plugins.
//  Most classes here should be instantiated only once and used
//  across all parallel algorithm instances
//


// Interface representing ways to handle a found solution
synchronized interface SolutionHandler {
    // method to be called when a valid solution is found
    void handle(MoveSequence solution);
    // method to be called when a dead end is reached
    void handleDead(MoveSequence moves);
}


synchronized class DebugHandler : SolutionHandler {
    import std.datetime: StopWatch;
    
    private immutable StopWatch sw;

    void handle(MoveSequence solution) {
        import std.stdio: writefln;
        writefln("notify solution after %d nsecs", sw.peek.nsecs);
    }

    void handleDead(MoveSequence moves) {
        import std.stdio: writefln;
        writefln("notify dead end after %d nsecs", sw.peek.nsecs);
    }
}


// Prints out the solution as a series of instructions to follow.
// The most basic handler which is still useful.
synchronized class PrintInstructionsHandler : SolutionHandler {

    // Keeps track of whether a solution was already found or not.
    // This makes it easier to make algorithms use it.
    private bool foundSolution = false;

    void handle(MoveSequence solution) {
        import std.stdio: writefln, readln;
        // if a solution was already found, we shouldn't report another one
        if (foundSolution) return;
        // then we make sure we register the solution we just got
        foundSolution = true;
        

        // and print it out.
        writefln("Instructions:");
        int i = 0;
        foreach (move; solution) {
            writefln("%d.\n%s", ++i, move.toString());
            readln;
        }
        writefln("Done.");
    }

    // this handler has no reason to consider dead ends directly
    void handleDead(MoveSequence moves) {}

}

// Handler which seeks out the highest score possible, then
// will return the best solution found, or if none, the best dead end.
synchronized class ScoreHunterHandler : SolutionHandler {
    // keeps track of whether a solution has been found
    private bool foundSolution = false;
    // keeps track of whether we're still looking for a better solution
    private bool keepSearching = true;
    // holds the solution with the best score so far
    private MoveSequence bestSolution = EmptyMoveSequence;
    // holds the best score so far
    private ulong bestScore = 0;

    // This handler uses a callback to handle the best solution it found
    private SolutionHandler callbackHandler;

    import std.datetime: Clock;

    private ulong initTime;
    private ulong goodEnoughSeconds; // number of seconds after which we should just take what we can get
    private ulong goodEnoughPoints;  // score which we don't care to be higher than

    // basic constructor
    this(shared SolutionHandler callback, ulong goodEnoughPoints = 5000, ulong goodEnoughSeconds = 7200) {
        this.callbackHandler = callback;
        this.goodEnoughSeconds = goodEnoughSeconds * 10000000; // convert from secs to hnsecs
        this.goodEnoughPoints  = goodEnoughPoints;
        this.initTime = Clock.currStdTime;
    }

    // call this method when a better score is no longer needed to handle the solution
    private void useCurrentSolution() {
        callbackHandler.handle(cast()bestSolution);
    }

    private bool isOverTime() {
        return (Clock.currStdTime - initTime) > goodEnoughSeconds;
    }

    private void resetTimer() {
        initTime = Clock.currStdTime;
    }

    void handle(MoveSequence solution) {
        import std.stdio: writefln;
        // if we hadn't yet found a solution,
        // we should reset the best score to 0 since any
        // solution is more valuable than a dead end.
        if (!keepSearching) return;
        if (!foundSolution) {
            bestScore = 0;
            foundSolution = true;
        }
        // then we calculate score and replace our best if it beats it
        ulong points = score(solution);
        if (points > bestScore) {
            if (points > 9900) {
                writefln("An aberrant score of %d was encountered; we're skipping it.", points);
                return; // A score above 9900 is impossible, so an error must have occurred.
            }
            bestScore = points;
            bestSolution = solution.asShared;
            writefln("Found a solution with a score of %d.", points);
            resetTimer();
            if (points > goodEnoughPoints) {
                writefln("That's better than the desired score of %d!!!", goodEnoughPoints);
                keepSearching = false;
                useCurrentSolution();
            }
        }
        if (isOverTime) {
            writefln("We didn't find a better score in %d seconds.", goodEnoughSeconds / 10000000);
            keepSearching = false;
            useCurrentSolution();
        }
    }

    // If we haven't found a solution, we may still want to choose
    // a losing game which scores well, so we need to handle them too.
    void handleDead(MoveSequence moves) {    
        import std.stdio: writefln;
        // if we've already found a solution, we don't need to take a failure into account
        if (!keepSearching) return;
        if (isOverTime) {
            writefln("We didn't find a better score in %d seconds.", goodEnoughSeconds / 10000000);
            keepSearching = false;
            useCurrentSolution();
        }
        if (foundSolution) return;
        ulong points = score(moves);
        if (points > bestScore) {
            bestScore = points;
            bestSolution = moves.asShared;
            writefln("Found a dead end with a score of %d.", points);
            resetTimer();
        }
    }

    // This helps us calculate the score which each game will receive
    ulong score(MoveSequence moves) {
        ulong sum = 0;
        foreach (move; moves.data[0..moves.length]) {
            sum += (move.groupSize) * (move.groupSize - 1); // the actual algorithm
        }
        return sum;
    }
}

// Handler which will report back the time of the fastest solution.
// That's all. Useful for benchmarking I guess?
synchronized class TimerSolutionHandler : SolutionHandler {
    import std.datetime: Clock;
    private ulong initTime;
    private bool hasFinished = false;
    private ulong deadEnds = 0;

    this() {
        this.initTime = Clock.currStdTime;
    }

    void handle(MoveSequence solution) {
        import std.stdio: writefln;
        if (hasFinished) return;
        writefln("Found a solution after %d hnsecs", Clock.currStdTime - initTime);
        hasFinished = true;
    }

    // we don't want no failures
    void handleDead(MoveSequence moves) { 
        import std.stdio: writefln;
        import core.atomic: atomicOp;
        if (hasFinished) return;
        deadEnds.atomicOp!"+="(1);

        if (deadEnds % 10000 == 0)
            writefln("found %d dead ends on the road to victory", deadEnds);
    }
}



// An interface representing the functionality of sorting moves
synchronized interface MovePrioritizer {
    BlockGroup[] prioritize(BlockGroup[] moves);
}

// Self-explanatory
synchronized class DoNothingPrioritizer : MovePrioritizer {
    BlockGroup[] prioritize(BlockGroup[] moves) {
        return moves;
    }
}

// Also self-explanatory
synchronized class ReversePrioritizer : MovePrioritizer {
    private MovePrioritizer prior;

    this() {
        this.prior = new shared DoNothingPrioritizer;
    }

    this(shared MovePrioritizer prior) {
        this.prior = prior;
    }

    BlockGroup[] prioritize(BlockGroup[] moves) {
        import std.algorithm: reverse;
        BlockGroup[] bg = prior.prioritize(moves);
        reverse(bg);
        return bg;
    }
}

// Sorts the next moves from most blocks to least
synchronized class BySizePrioritizer : MovePrioritizer {
    BlockGroup[] prioritize(BlockGroup[] moves) {
        import std.algorithm: sort;
        import std.array: array;
        return moves.sort!((a, b) => a.groupSize > b.groupSize).array;
    }
}
