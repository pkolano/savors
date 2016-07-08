Synchronization And Visualization Of aRbitrary Streams (Savors)
===============================================================

Note that this documentation is still a work in progress so is
incomplete in various aspects and is probably not in optimal form.
It should be sufficient for most purposes, however, until better
documentation can be written.  For full details of the Savors
architecture, see https://pkolano.github.io/papers/vda15.pdf.


1. Introduction

    Savors is a framework for Synchronization And Visualization Of aRbitrary
    Streams.  The goal of Savors is to supercharge the command-line tools
    already used by administrators with powerful visualizations that help them
    understand the output much more rapidly and with far greater scalability
    across systems.  Savors not only supports the output of existing commands,
    but does so in a manner consistent with those commands by combining the
    line-editing capabilities of vi, the rapid window manipulation of GNU
    screen, the power and compactness of perl expressions, and the elegance of
    Unix pipelines.  Savors was designed to support "impromptu visualization",
    where the user can simply feed in the commands they were already using to
    create alternate views with optional on-the-fly aggregation of information
    across many systems.  In this way, visualization becomes part of the
    administrator's standard repertoire of monitoring and analysis techniques
    with no need for a priori aggregation of data at a centralized resource or
    conversion of the data into a predefined format.

    Savors is unique in its support of all four combinations of single/multiple
    data streams and single/multiple views.  That is, Savors can show any
    number of data streams either consolidated in the same view or spread out
    across multiple views.  In multi-data scenarios, data streams can be
    synchronized by time allowing even distributed data streams to be viewed in
    the same temporal context.  In single-data multi-view scenarios, views are
    updated in lockstep fashion so they show the same data at the same time.
    Together with its integrated parallelization capabilities, this allows
    Savors to easily show meaningful results from across even very large
    installations.


2. Quick Start

    This section assumes Savors has already been installed according to the
    details in "INSTALL".  To quickly see Savors in action, do the following:

        (1) run "savors"
        (2) type ":r "
        (3) type in one of the listed saved view names and hit return
        (4) hit return again
        (5) C-c to stop, :q to exit

    Note that Savors is not compatible with tiling window managers
    (e.g. ratpoison) as it does its own tiling.


3. Savors Console

    Savors is invoked by calling the "savors" executable.  This brings up a
    console window through which all interaction is carried out.  The command
    line options include:

        -c, --command=CMD    run command line without console
            --conf=FILE      load config from file
            --frame          show frame on view windows
            --geometry=GEOM  geometry of console window
        -h, --help=TOPIC     help with optional topic one of {bind,data,ex,view
                                axis,chart,cloud,graph,grid,map,rain,tree
            --smaxx=REAL     max fraction of screen width to use for views
            --smaxy=REAL     max fraction of screen height to use for views
            --tcp            use tcp sockets instead of unix sockets
            --vgeometry=GEOM geometry of screen area to use for views

    The main form of interaction is a "vi-like" command line buffer in the
    upper right.  Just like vi, it starts in "escape-mode" so requires a/A/i/I
    to enter insertion mode or "ex-mode" colon commands to load/save views or
    exit.  Saved views and some options are stored in ~/.savorsrc.
    Context-sensitive help is shown beneath the editor depending on the console
    mode and position in the text.

    3.1. Initiating views

        To visualize a command pipeline, type/load the pipeline into the
        buffer and hit return.  A pipeline consists of 3 parts that will be
        discussed throughout the remainder:

            (1) the command or piped sequence of commands to visualize
            (2) directives on how to manipulate the command output
                given through a pseudo-env environment
            (3) how to display the data through a supported view

        The final command pipeline will be in the form:

            env OPT=VAL... (ARGS... |...) |VIEW ...

        For example, the following shows a simple "hello world" example:

            env repeat=1 echo hello world |rain

    3.1. Saving/Loading Views

        Views are saved/loaded via "ex-mode" similar to that of vi.  To enter
        ex-mode, type ":" when in escape mode (i.e. when the green "insert"
        button is not shown), which can always be entered by hitting the escape
        key.

        To save a view called "name", use ":w name" then hit return.  Note
        that ":w" by itself does not save a view previously loaded as vi would.
        This behavior will be changed to more closely emulate vi in the future.

        To load a view called "name", use ":r name" then hit return.  When
        ":r" is entered, the help region will fill with the predefined views
        available.  As more text is entered (e.g. ":r tree"), the help region
        will fill with the possible completions.  Tab may be used to
        automatically complete the name with the one that matches the prefix or
        with a partial completion and the names remaining in the help region.
        Hit return to load, then return to run.

        To save the canvas of the active window, use ":s file" then hit
        return.  Note that files are written in postscript format and that the
        file names of multi-view windows are saved to files with -i in them for
        each i from 1 to the number of windows (e.g. "foo.ps" becomes "foo-i.ps"
        and "foo" becomes "foo-i").  Currently, these files must be stitched
        together manually using an external tool such as ImageMagick (import
        -append and +append options).  In the future, they may be combined
        automatically.

        Like vi, ":q" quits.  Note that unlike vi, unsaved buffers will not
        prevent program exit (i.e. ":q" currently acts like vi ":q!").  This
        behavior will be changed to more closely emulate vi in the future.

        In summary, ex-mode supports the following commands:

                 :q - quit savors
            :r NAME - read command from name
            :s FILE - save window canvas to file
            :w NAME - store command as name

        and the following key bindings:

            BackSpace - remove prev char
            Control-c - abort ex mode
               Escape - abort ex mode
                  Tab - complete :r name

    3.2. Window/Region/Layout Manipulation

        The Savors model is based on GNU screen and the author's screenwm
        extension (http://screenwm.sf.net).  The key bindings have been
        streamlined to be a mix of vi escape mode and screen commands to avoid
        the use of the screen C-a meta key.

        The console always starts out with a single window in a single region in
        a single layout.  Just like screen, there can be multiple windows per
        region ("c" to create) with shuffling between them ("n" next, "p"
        previous).  Just like screenwm or screen >= 4.1, regions can be split
        both horizontally with "s" or vertically with "S".  Also just like
        screenwm or screen >= 4.1, there can be multiple layouts ("C" to
        create) where a layout may contain any arrangement of regions with
        shuffling between them ("N" next, "P" previous).  In general, layouts
        are manipulated with the capital version of the window commands (e.g.
        "c" creates window, "C" creates layout).  Movement between regions is
        achieved using capital vi movement keys (i.e. HJKL) or
        Shift-{Left,Down,Up,Right}.

        Each window has its own command buffer used to create new
        visualizations.  By default, all views will be synchronized by time.
        Since this is not always desired, especially with computationally
        expensive views such as graph/tree, or with data across multiple regions
        of time, a "sync=" directive can be used to specify the group with which
        to sync each data stream.  The default group is "1".  Use a group of "0"
        to be completely unsynchronized.  Note that when the data generator
        portion of a command matches exactly, the views will share the data
        instead of spawning a new command.  

        Any/all windows can be paused and stepped.  Use "z" to stop the current
        window and any windows in the same sync group.  Use "Z" to stop all
        windows.  Use "j" or the Down key to step forward (stepping back is not
        yet implemented).  Use "z" or "Z" again to unpause.  You can pause all
        windows, then unpause some of them, and vice-versa depending which
        window you are in.

    3.3. Console escape-mode bindings

        3.3.1. Console mode

            : - ex mode

            Escape - escape mode

        3.3.2. Cursor movement

            b - back word
            B - back non-space
            e - end word
            E - end non-space
            h - cursor left
            w - next word
            W - next non-space
            x - delete char

            0 - line start
            $ - line end
            l - cursor right
            ^ - line non-space start

            BackSpace - cursor left
            Left - cursor left
            Right - cursor right
            Space - cursor right

        3.3.3. Text manipulation

            a - append cursor
            A - append at end
            d - delete word
            D - delete to end
            i - insert cursor
            I - insert at start
            y - yank line
            Y - yank line
            ] - paste line

            Delete - delete char

        3.3.4. Window manipulation

            c - create window
            C - create layout
            H - layout left
            J - layout down
            K - layout up
            L - layout right
            n - next window
            N - next layout
            p - prev window
            P - prev layout
            q - unfocus region (not yet implemented)
            Q - focus region (not yet implemented)
            r - remove window (not yet implemented)
            R - remove layout (not yet implemented)
            s - horizontal split
            S - vertical split
            X - delete region

            Shift-Down - layout down
            Shift-Left - layout left
            Shift-Right - layout right
            Shift-Up - layout up

        3.3.5. View/Data manipulation

            j - step forward
            k - step back (not yet implemented)
            z - pause window
            Z - pause all

            Control-c - abort view
            Down - step forward
            Return - execute view
            Up - step back (not yet implemented)
 

4. Command Pipelines and Data Handling

    To demonstrate the anatomy of a command pipeline and illustrate various
    features, the process of creating a treemap of user cpu activity via top
    across four hosts will be used as a running example.  To see what this looks
    like on a single system, type ":r tree_top" then two returns in the console.
    The normal top mode manipulates the terminal window via curses, which isn't
    supported by Savors, so the "-b" option is needed to force the non-curses
    batch mode.  To keep top producing data periodically, "-d 10" is used to
    update every 10 seconds.  Hence, the basic data generator is:

        top -b -d 10

    To achieve a consolidated view across four systems (which will be called
    host[1-4]), however, we must ssh to each and run the same command.  Now, it
    is possible to create a command line to do this and consolidate everything
    together outside of Savors, but Savors has a more efficient way of handling
    this using its built-in "data directives", which describe how to produce
    and/or transform the data.  Data directives are specified using a
    "pseudo-env" command (i.e. similar to but not actually invoking the standard
    env command) where directive names are variables and directive contents are
    the values.  In this case, to run the same command over a set of systems,
    the "data=" setting can be used:

        env data=1,2,3,4 ssh hostfD top -b -d 10 ...

    Note that the data directive also supports the form i-j so this case could
    also have been written "data=1-4".  "fD" is one of a few special variables
    that is replaced by the various values of the data directive, so in this
    case, this creates 4 data streams composed of the top command on each host
    host[1-4].  As will be seen later, this fD variable is also available in the
    view specification to distinguish where each line of data came from.

    Since a primary function of Savors is to synchronize different streams via
    time, Savors needs to understand the time associated with every line of
    command output.  You can either (1) not give a time, in which case the
    current time will be assigned, (2) give a "sync=0" directive, in which time
    is disregarded, or (3) give a "time=" directive to tell which fields
    constitute the time.  The top command is a special case because the time
    for many lines of output is only given on one line during each iteration.
    For cases like this, there is a "time_grep=" directive, which specifies a
    regular expression that should match only when the line containing the time
    is encountered.  In the case of top, we see the following output with the
    time:

        top - 16:30:06 up 42 days, 8:31, 122 users, load average: ...

    which occurs when "top" is found at the left margin, specified as the
    regex "^top" in perl syntax (which all Savors regexes assume).  We must also
    tell Savors where in this line the time occurs.  This is done using a "field
    specifier", which can be either a single field like "f1", a field sequence
    like "f2-f5", a list of fields like "f3,f7,f13", or "fL", which corresponds
    to the last field.  Fields are assumed to be whitespace separated and start
    from f1 so in this case, we would use "time=f3" as f1 is "top", f2 is "-",
    and f3 is "16:30:06".  If input data is split by something other than or in
    addition to whitespace, the "split=" directive can be used to specify the
    regex corresponding to the field separator (e.g. split='\s+|,' would split
    by both whitespace and commas).

    In the command output, there may be lines that we don't want to visualize
    or that don't follow the format we expect.  For example, each top iteration
    looks like this:

        top - 16:30:06 up 42 days, 8:31, 122 users, load average: ...
        Tasks: 1408 total, 2 running, 1404 sleeping, 2 stopped, 0 zombie
        Cpu(s): 0.6%us, 1.0%sy, 0.0%ni, 98.1%id, 0.3%wa, 0.0%hi, 0.0%si, 0.0%st
        Mem: 64402M total, 55083M used, 9319M free, 189M buffers
        Swap: 97346M total, 766M used, 96579M free, 36911M cached

          PID USER      PR  NI  VIRT  RES  SHR S %CPU %MEM    TIME+  COMMAND
        47647 someuser  20   0  9984 2104  772 R    6  0.0   0:00.05 top
        ...

    Since we are trying to visualize cpu activity at the process level, we
    only want the pid/user/.../cmd lines.  While this could again conceivably be
    done with an additional grep in the command pipeline, Savors again has a
    built-in way to handle this common case.  The "grep=" and "grep_v="
    directives tell Savors the lines that you do and don't care about,
    respectively, just like the standard grep and grep -v commands, but again
    with perl regexes.

    In this case, we are trying to get user cpu activity, so we need to keep
    the process lines while eliminating root processes.  For this, we use the
    "grep" directive with a regex '^\s*\d', which means keep lines that begin
    with a digit (possibly preceded by whitespace) and the "grep_v" directive
    with a regex ' root ', which means eliminate that have root surrounded by
    spaces.  This leaves our final data generator with directives as:

        env grep='^\s*\d' grep_v=' root ' time=f3 time_grep='^top' \
            data=1,2,3,4 ssh hostfD top -b -d 10 ...

    A summary of supported directives with examples is shown below.  Better
    documentation of these options will be provided in the future.

             color=EVAL - expression to color by            color=f19
            ctype=CTYPE - method to assign colors by        ctype=hash:ord
             cut=FIELDS - keep matching fields              cut=f1,f3-f5,f7-fL
           data=STRINGS - create parallel data streams      data=host1,host2
             grep=REGEX - keep matching lines               grep='^d'
           grep_v=REGEX - discard matching lines            grep_v='^D'
            host=STRING - host to run data server on        host=host1
    label=STRING|FIELDS - default field labels              label=time,f1-fL
       label_grep=REGEX - line containing labels            label_grep='^PID'
          layout=LAYOUT - layout for view directive         layout=2x2
            repeat=REAL - repeat ARGS every interval        repeat=60
            replay=REAL - replay file ARGS[0] at speed      replay=2
       sed=REGEX/STRING - replace matches with string       sed='\[\d+\]/'
            split=REGEX - field separator                   split=','
               sync=INT - synchronization group             sync=99
               tee=FILE - write output to file              tee=/tmp/out
             tee_a=FILE - append output to file             tee_a=/tmp/out
            time=FIELDS - fields representing date/time     time=f1-f5
        time_grep=REGEX - line containing time/iteration    time_grep='^top'
           view=STRINGS - create multi-view windows         view=1-4


5. Views

    The final command in each pipeline specifies how to visualize the data
    using the view type as the command with any desired options relevant to that
    type.  In the running example, we want to show a treemap so would use:

        |tree ...

    The Savors treemap is a squarified treemap, which is a hierarchical tree
    of rectangular regions.  A given region shows the percentage of the parent's
    total of some valuation that the given region represents.  For the running
    example, we want the valuation to be cpu activity.

    To specify the hierarchy of regions, the tree view uses a list of
    expressions given in the --fields option (this option is used in all view
    types).  If we look at the top header, we can see the mapping between field
    numbers and what each field represents:

        PID USER PR NI VIRT RES SHR S  %CPU %MEM TIME+ COMMAND
         f1  f2  f3 f4  f5   f6  f7 f8  f9   f10  f11    f12

    For our treemap, we would like the highest level box to be the host where
    the data came from.  In Savors, --fields is a comma-separated list of
    arbitrary perl expressions that are evaluated dynamically together with
    the various special "f*" variables.  Note that expressions of anything
    besides simple fields or lists of fields must be quoted.  We can create the
    highest level with the expression 'q(host).fD', which is the string "host"
    concatenated with the particular data value that the data came from.  We
    would then like the regions to break down by user, command, and finally cpu
    activity.  We will base the cpu activity on the %CPU field.  Since this can
    often be zero, we will add a small value so that all processes are
    represented.  Our view specification is now:

        |tree --fields='q(host).fD',f2,f12,f9+.01

    Another important consideration is how to color the treemap.  In the treemap
    and other views, the --color option specifies how colors will be assigned.
    Like each expression in the --fields list, --color represents an arbitrary
    perl expression.  It will typically be a "f*" variable, but is not limited
    to that.  In the case of our treemap, we will color by the command using
    "--color=f12", hence we will easily be able to distinguish the same command
    running on different hosts.  The final option we will use is the --period
    option to specify how much time within the data that we wish to show at
    once.  Since top is updating every 10 seconds, we will use "--period=10"
    instead of the default of 1, making our final view specification:

        |tree --fields='q(host).fD',f2,f12,f9+.01 --color=f12 --period=10

    This makes our full command:

        env grep='^\s*\d' grep_v=' root ' time=f3 time_grep='^top' \
            data=1,2,3,4 ssh hostfD top -b -d 10 \
            |tree --fields='q(host).fD',f2,f12,f9+.01 --color=f12 --period=10

    A number of convenience functions can be used in --fields expressions.  Each
    function takes a single argument (e.g. --fields='iplat(f4),iplong(f4)').
    The currently supported functions include:

        ipanon - anonymize IP address
        ipcity - city name of IP address
        ipcountry - country name of IP address
        ipcountry2 - country code of IP address
        iplat - latitude of IP address
        iplong - longitude of IP address
        ipstate - state name of IP address
        ipstate2 - state code of IP address
        ipzip - zip code of IP address
        hostanon - anonymize host name
        hostip - IP address of host name
        useranon - anonymize user name

    The following sections summarize the available views and their options.

    5.1. Axis (multi-axis relationships)

        USAGE: env OPT=VAL... (ARGS... |...) |axis ...

        EXAMPLE: axis --color=f19 --fields=f3,f5,f7,f9 --label=si,sp,di,dp

        TYPES: circle,hive,parallel,star

        OPTIONS:                                        EXAMPLES:
               --color=EVAL - expression to color by        --color=f19
              --ctype=CTYPE - method to assign colors by    --ctype=hash:ord
                --dash=EVAL - condition to dash edge        --dash="f21 eq 'out'"
             --fields=EVALS - expressions to plot           --fields=f3,f5,f7,f9
            --label=STRINGS - labels for axes               --label=sip,sp,dip,dp
                   --legend - show color legend             --legend
                --lines=INT - data lines to show            --lines=20
                 --max=INTS - max value of each field       --max=100,10,50
                 --min=INTS - min value of each field       --min=50,0,10
              --period=REAL - time between updates          --period=3
             --title=STRING - title of view                 --title="CPU Usage"
                --type=TYPE - type of plot                  --type=hive

    5.2. Chart (various charts)

        USAGE: env OPT=VAL... (ARGS... |...) |chart ...

        EXAMPLE: chart --color=f2 --fields=f3 --type=bar --label=cpu

        TYPES: bar,direction,errorbar,horizontalbar,line,linepoint,mountain,
               pareto,pie,point,split,stackedbar

        OPTIONS:                                           EXAMPLES:
               --color=EVAL - expression to color by           --color='q(host).fD'
              --ctype=CTYPE - method to assign colors by       --ctype=hash:ord
              --date=STRING - strftime format for time axis    --date='%m/%d %T
             --fields=EVALS - expresssions to plot             --fields=f22+f23
            --fields2=EVALS - secondary expressions to plot    --fields2=f4-f10
             --label=STRING - label of y axis                  --label=Bytes/Sec
            --label2=STRING - label of secondary y axis        --label2=Calls
                   --legend - show color legend                --legend
                --lines=INT - number of time lines to show     --lines=60
                 --max=INTS - max value of each field          --max=100,10,50
                 --min=INTS - min value of each field          --min=50,0,10
              --period=REAL - time between updates             --period=15
               --splits=INT - number of splits to plot         --splits=10
             --title=STRING - title of view                    --title="CPU Usage"
                --type=TYPE - type of chart                    --type=stackedbar
               --type2=TYPE - type of secondary chart          --type2=line

    5.3. Cloud (word cloud)

        USAGE: env OPT=VAL... (ARGS... |...) |cloud ...

        EXAMPLE: cloud --color=f12 --fields=f2,f12 --ngram=2 --period=10

        OPTIONS:                                       EXAMPLES:
              --color=EVAL - expression to color by        --color=f12
              --count=EVAL - expression to increment by    --count='f13+f14'
             --ctype=CTYPE - method to assign colors by    --ctype=hash:ord
            --fields=EVALS - expressions denoting words    --fields=f2,f12
               --font=PATH - path to alternate font        --font=/.../Vera.ttf
                  --legend - show color legend             --legend
                --max=INTS - max value of each field       --max=100,10,50
                --min=INTS - min value of each field       --min=50,0,10
               --ngram=INT - length of word sequences      --ngram=2
             --period=REAL - time between updates          --period=15
            --title=STRING - title of view                 --title="CPU Usage"

    5.4. Graph (various graphs)

        USAGE: env OPT=VAL... (ARGS... |...) |graph ...

        EXAMPLE: graph --color=f2 --fields=f15,f1 --period=15 --type=fdp

        TYPES: circo,dot,easy,fdp,neato,sequence,sfdp,twopi

        OPTIONS:                                           EXAMPLES:
                --color=EVAL - expression to color edges by    --color=f6
            --cdefault=COLOR - default node/edge color         --cdefault='#ccff00'
               --ctype=CTYPE - method to assign colors by      --ctype=hash:ord
              --fields=EVALS - expressions denoting edges      --fields=f4,f6
                --label=EVAL - expression to label edges by    --label=f2
                    --legend - show color legend               --legend
                  --max=INTS - max value of each field         --max=100,10,50
                  --min=INTS - min value of each field         --min=50,0,10
               --period=REAL - time between updates            --period=15
                 --swap=EVAL - condition to reverse edge       --swap='f5>10000'
               --timeout=INT - easy layout timeout             --timeout=60
              --title=STRING - title of view                   --title="CPU Usage"
                 --type=TYPE - type of graph                   --type=circo

    5.5. Grid (gridded plots)

        USAGE: env OPT=VAL... (ARGS... |...) |grid ...

        EXAMPLE: grid --color=fD --fields=f22+f23 --label=fD --max=125

        TYPES: graph,heat,set

        OPTIONS:                                       EXAMPLES:
             --ctype=CTYPE - method to assign colors by    --ctype=hash:ord
            --fields=EVALS - expressions to plot           --fields=f4-f123
              --label=EVAL - expression to label by        --label=fD
                  --legend - show color legend             --legend
               --lines=INT - number of periods to show     --lines=20
                --max=INTS - max value of each field       --max=100,10,50
                --min=INTS - min value of each field       --min=50,0,10
             --period=REAL - time between updates          --period=15
               --swap=EVAL - condition to reverse edge     --swap='f5>10000'
            --title=STRING - title of view                 --title="CPU Usage"
               --type=TYPE - type of grid                  --type=set

    5.6. Map (world/country/shape map)

        USAGE: env OPT=VAL... (ARGS... |...) |map ...

        EXAMPLE: map --color=f12 --fields=f3,f7 --file=us

        TYPES: arc,bubble,heat

        OPTIONS:                                       EXAMPLES:
             --attr=STRING - attribute containing tags     --attr=fips
              --color=EVAL - expression to color by        --color=f19
             --ctype=CTYPE - method to assign colors by    --ctype=hash:ord
               --dash=EVAL - condition to dash edge        --dash="f21 eq 'out'"
            --fields=EVALS - expressions denoting edges    --fields=f3,f7
               --file=FILE - name of shape file            --file=us
                  --legend - show color legend             --legend
                --max=INTS - max value of each field       --max=100,10,50
                --min=INTS - min value of each field       --min=50,0,10
            --no-tags=TAGS - tags to exclude               --no-tags=02,15,72,78
             --period=REAL - time between updates          --period=15
               --tags=TAGS - tags to include               --tags=ca,mx,us
            --title=STRING - title of view                 --title="CPU Usage"
               --type=TYPE - type of map                   --type=arc

    5.7. Rain (text/binary rainfall)

        USAGE: env OPT=VAL... (ARGS... |...) |rain ...

        EXAMPLE: rain --color=f19 --fields=f17,f18 --hex --size=1

        OPTIONS:                                       EXAMPLES:
             --color=EVAL - expression to color by        --color=f19
            --ctype=CTYPE - method to assign colors by    --ctype=hash:ord
           --fields=EVALS - subset of fields to show      --fields=f17,f18
                    --hex - show binary data as hex       --hex
                 --legend - show color legend             --legend
               --max=INTS - max value of each field       --max=100,10,50
               --min=INTS - min value of each field       --min=50,0,10
            --period=REAL - time between updates          --period=3
               --size=INT - font size or 1 for binary     --size=1
           --title=STRING - title of view                 --title="CPU Usage"

    5.8. Tree (various treemaps)

        USAGE: env OPT=VAL... (ARGS... |...) |tree ...

        EXAMPLE: tree --color=f2 --fields=f3,f2,f4,f5 --period=60

        TYPES: histo,squarified,weighted

        OPTIONS:                                       EXAMPLES:
              --color=EVAL - expression to color by        --color=f2
             --ctype=CTYPE - method to assign colors by    --ctype=hash:ord
               --face=FONT - alternate font face           --face=Arial
            --fields=EVALS - expressions to plot           --fields=f28,f2,f3+.01
               --font=PATH - path to alternate font        --font=/.../Vera.ttf
                  --legend - show color legend             --legend
                --max=INTS - max value of each field       --max=100,10,50
                --min=INTS - min value of each field       --min=50,0,10
             --period=REAL - time between updates          --period=15
               --show=INTS - max items for each level      --show=10,5,10
            --title=STRING - title of view                 --title="CPU Usage"
               --type=TYPE - type of tree                  --type=histo


6. Advanced Usage

    6.1. Console-less operation

        A view can be run without the console by using the --command option
        set to either a full command (that would normally be entered in the
        console editor) or to the name of a view saved with :w in the console.
        The geometry of this window can be specified using --vgeometry.  In this
        mode of operation, C-c kills the window and C-s saves the window canvas
        (to the value of the "snap_file" setting in savorsrc or
        savors-snapshot.ps if snap_file is not specified).

        This feature can be used to easily create visual versions of
        standard/useful commands that can be deployed for all users without
        the need for any Savors knowledge.

    6.2. Multi-view windows

        A single window can be arbitrarily subdivided into subwindows in a
        single command, which can be used to quickly generate parameter studies.
        The "view=" directive specifies the parameters to use in each view.  The
        "layout=" directive specifies the arrangement of windows in the current
        region.  Layouts are any combination of grids (WxH), vertical splits
        (L|R), and horizontal splits (T-B), with grids having a higher
        precendence than splits.  For vertical splits, the shorthand "I|J" for
        integers I and J may be used to represent "1xI|1xJ".  Similarly, for
        horizontal splits, the shorthand "I-J" may be used to represent
        "Ix1-Jx1".  For example,

            layout='(4-1)|(3x2)'

        would represent a layout where the left half of the window has 4
        subwindows on top with 1 subwindow on the bottom and the right half of
        the window has 6 subwindows arranged in 2 rows of 3 columns.

        A new subwindow is spawned for each view value.  Before spawning, the
        special variable "fV" is replaced by each value in data generator
        pipelines and view options.  For example:

            env view=1-4 layout=2x2 ssh hostfV ...

        would create a view for each of four hosts host[1-4] in a 2x2 grid.

    6.3. Multi-host displays

        Displays that consist of multiple monitors connected to separate hosts
        can be supported by configuring the "displays" and "wall" configuration
        items.  The wall setting specifies the layout of the displays (only grid
        layouts are supported).  The displays setting specifies a list of
        host/$DISPLAY pairs for each monitor in the grid.  Columns of each row
        are mapped to displays in left to right order before the row below is
        mapped.

        Note that each display host must be accessible via non-interactive ssh
        authentication (e.g. pubkey or hostbased) and all corresponding ssh
        public host keys must be in the user's or system's known host file.


7. Notes

    Savors is in an alpha state so it is quite likely it will crash at some
    point as error handling and input validation are minimal.  In some
    scenarios, data-related processes may not always be cleaned up
    appropriately.  Whatever the cause, processes may be killed quickly using
    "killall perl" or "killall /usr/bin/perl" depending on system type (care
    should be taken, of course, not to kill unrelated processes).

    The "pie" chart type has broken colorization in some cases due to a bug in
    the underlying charting module used.


8. Contact

    Questions, comments, fixes, and/or enhancements welcome.

    --Paul Kolano <paul.kolano@nasa.gov>

