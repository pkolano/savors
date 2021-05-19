![console](https://cloud.githubusercontent.com/assets/20344426/24267319/290984c0-0fc7-11e7-8134-42625b3c1fb3.png)
![axis_ps](https://cloud.githubusercontent.com/assets/20344426/24267326/2d2ce268-0fc7-11e7-9163-3a42f0b64432.png)
![chart_ltop](https://cloud.githubusercontent.com/assets/20344426/24267339/3638c610-0fc7-11e7-936b-fad72afe0a66.png)
![graph_top](https://cloud.githubusercontent.com/assets/20344426/24267347/3a533a00-0fc7-11e7-80dd-4f7496001fe8.png)
![grid_mount](https://cloud.githubusercontent.com/assets/20344426/24267351/3d658342-0fc7-11e7-8682-83d065088d7d.png)
![tree_qstat](https://cloud.githubusercontent.com/assets/20344426/24267356/4305c1ea-0fc7-11e7-948e-29b9d5a426f9.png)


Synchronization And Visualization Of aRbitrary Streams (Savors)
===============================================================

Savors is a framework for Synchronization And Visualization Of
aRbitrary Streams.  The goal of Savors is to supercharge the
command-line tools already used by administrators with powerful
visualizations that help them understand the output much more rapidly
and with far greater scalability across systems.  Savors not only
supports the output of existing commands, but does so in a manner
consistent with those commands by combining the line-editing
capabilities of vi, the rapid window manipulation of GNU screen, the
power and compactness of perl expressions, and the elegance of Unix
pipelines.  Savors was designed to support "impromptu visualization",
where the user can simply feed in the commands they were already using
to create alternate views with optional on-the-fly aggregation of
information across many systems.  In this way, visualization becomes
part of the administrator's standard repertoire of monitoring and
analysis techniques with no need for a priori aggregation of data at a
centralized resource or conversion of the data into a predefined format.

Savors is unique in its support of all four combinations of
single/multiple data streams and single/multiple views.  That is, Savors
can show any number of data streams either consolidated in the same view
or spread out across multiple views.  In multi-data scenarios, data
streams can be synchronized by time allowing even distributed data
streams to be viewed in the same temporal context.  In single-data
multi-view scenarios, views are updated in lockstep fashion so they show
the same data at the same time.  Together with its integrated
parallelization capabilities, this allows Savors to easily show
meaningful results from across even very large installations.

A subset of Savors is in active production at the NASA Advanced
Supercomputing Facility (https://www.nas.nasa.gov/hecc/support/kb/entry/552).

For full details of the Savors architecture, see
https://pkolano.github.io/papers/vda15.pdf.  For installation details,
see "INSTALL".  For usage details, see the man pages (viewable with
"nroff -man" before installation) in the "doc" directory ("savors.1" for
general overview and usage, "savorsrc.5" for configuration and the
others as referenced).

Questions, comments, fixes, and/or enhancements welcome.

--Paul Kolano <paul.kolano@nasa.gov>
