# db.tcl -- Collection of low-level Wiki database accessors and mutators
# originally written by Jean-Claude Wippler, 2000..2007 - may be used freely
#
# admin:
# Wiki -
# WikiDatabase - open the Wiki database
#
# accessors:
# GetTitle - get page's title by id
# GetPage - get page's content by id
# pagevars - get vars from page view
#
# mutators:
# FixPageRefs - traverse pages building a reference view
# SavePage - save a changed page to page view
# DoCommit - commit db changes
# DoSync - sync Wikit to the contents of a URL

# Structure of the database (wdb)
# 2 views: 'pages' and 'refs'.

# "pages" is the main view. It contains all pages managed by the wiki,
# and their contents.

# "refs" is a view with <from,to> page id pairs, one for each hyperlink,
# used to generate the back-references page (N!), for example.

# pages
# - string      name    Title of page
# - string      page    Contents of page.
# - integer     date    date of last modification of the page as time_t value.
# - string      who     some string identifying who modified the page last.
# - subview     changes Change history of the page
#    - string      name       Title of an earlier version of the page
#    - integer     date       Date of last modification of the earlier version
#    - string      who        String identifying the person who last modified
#                               the earlier version
#    - subview     diffs      Differences between the next more recent version
#                              and the earlier version
#       - integer    from       Index of the first changed line in the newer
#                                page for one region of changes.
#       - integer    to         Index of the last changed line in the region
#                                and the newer page
#       - string     old        Text that the new lines replace in the
#                                earlier version.
#
# If to < from, then text was deleted from the earlier version of the page,
# and must be inserted before the line numbered, 'from' when reconstructing
# the old version
# If old is empty, then text was inserted between the earlier and later
# versions, and must be deleted when reconstructing to the old version.
# Otherwise, text was modified between the two versions, and 'old' is
# the text that will replace lines 'from'-'to', inclusive.  'old' is a
# Tcl list containing the lines, rather than a block of text.

# refs
# - integer	from	id of the page containing the reference
# - integer	to	id of the referenced page

# Note II: The code here is able to maintain external copies for all
# pages (and all revisions) and an external log of changes. This
# functionality is activated by having a directory matching the value
# of the $WIKI_HIST environment variable.  The system only tracks dates
# and ip's inside the datafile for the recent page, not page contents.

package provide Wikit::Db 1.2
package require Wikit::Utils
package require Wikit::Format
package require struct::list

if {[info commands Debug.error] eq {}} {
  proc Debug.error {args} {
    puts stderr $args
  }
}

namespace eval Wikit {
  # accessors
  namespace export pagevars Wiki WikiDatabase GetTitle GetPage pagevars pagevarsDB
  namespace import ::Wikit::Format::*

  # mutators
  namespace export SavePage SavePageDB DoCommit DoSync FixPageRefs

  variable readonly -1	;# use the file permissions
  variable mutex ""	;# mutex for locking at SavePageDB

  # Code for opening, closing, locking, searching, and modifying views

  proc Wiki {name args} {
    if {$name == "-"} {
      set page [lindex [split [lindex $args 0] "/"] end]
      catch { set name [mk::get wdb.pages!$page name] }
    }
    link - [Wikit::Format::quote $name] [join $args ?]
  }

  proc WikiDatabase {name {db wdb} {shared 0}} {
    variable readonly
    variable wikifile $name

    if {[lsearch -exact [mk::file open] $db] == -1} {
      if {$readonly == -1} {
        if {[file exists $name] && ![file writable $name]} {
          set readonly 1
        } else {
          set readonly 0
        }
      }

      set flags {}
      if {$readonly} {
        lappend flags -readonly
        set tst readable
      } else {
        set tst writable
      }

      if {$shared} {
        lappend flags -shared
      }

      set msg ""
      if {[catch {eval mk::file open $db $name -nocommit $flags} msg]
          && [file $tst $name]} {

        # if we can write and/or read the file but can't open
        # it using mk then it is almost always inside a starkit,
        # so we copy it to memory and open it from there

        set readonly 1
        mk::file open $db
        set fd [open $name]
        mk::file load $db $fd
        close $fd
        set msg ""
      }

      if {$msg != "" && ![string equal $msg $db]} {
        error $msg
      }
      if {1} {
        # temporarily stop doing this - it hangs the system
        # when db is corrupt.
        mk::view layout $db.pages {
          name
          page
          date:I
          who
          {changes {
            date:I
            who
            delta:I
            {diffs {
              from:I to:I old
            }}
          }}
        }
        
        mk::view layout $db.refs	{from:I to:I}
      }

      # if there are no references, probably it's the first time, so recalc
      if {!$readonly && [mk::view size $db.refs] == 0} {
        # this can take quite a while, unfortunately - but only once
        ::Wikit::FixPageRefs
      }
    }
  }

  # get page info into specified var names
  proc pagevarsDB {db num args} {
    # mk::get returns an item, not a list, if given a single property name
    if {[llength $args] == 1} {
      uplevel 1 [list set $args [mk::get $db.pages!$num $args]]
    } else {
      foreach x $args y [eval mk::get $db.pages!$num $args] {
        uplevel 1 [list set $x $y]
      }
    }
  }

  proc pagevars {num args} {
    set num [scan $num %d] ;# 2005-02-17 get rid of leading zeros
    # mk::get returns an item, not a list, if given a single property name
    if {[llength $args] == 1} {
      uplevel 1 [list set $args [mk::get wdb.pages!$num $args]]
    } else {
      foreach x $args y [eval mk::get wdb.pages!$num $args] {
        uplevel 1 [list set $x $y]
      }
    }
  }

  proc GetTitle {id {db wdb}} {
    set title [mk::get $db.pages!$id name]
    return $title
  }

  proc GetPage {id {db wdb} {guiMode 0}} {
    switch $id {
      2		{ SearchResults [SearchList] }
      4		{ RecentChanges $db $guiMode}
      default	{ return [mk::get $db.pages!$id page] }
    }
  }

  #----------------------------------------------------------------------------
  #
  # ListPageVersionsDB --
  #
  #	Enumerates the available versions of a page in the database.
  #
  # Parameters:
  #     db - Handle to the Wiki database
  #     id - Row id in the 'pages' view of the page being queried.
  #     limit - Maximum number of versions to return (default is all versions)
  #     start - Number of versions to skip before starting the list
  #		(default is 0)
  #
  # Results:
  #	Returns a list of tuples comprising the following elements
  #	    version - Row ID of the version in the 'changes' view,
  #                   with a fake row ID of one past the last row for
  #		      the current version.
  #         date - Date and time that the version was committed,
  #                in seconds since the Epoch
  #         who - String identifying the user that committed the version
  #
  #----------------------------------------------------------------------------

  proc ListPageVersionsDB {db id {limit Inf} {start 0}} {

    # Special case for the fake pages

    switch $id {
      2 - 4 {
        return [list [list 0 [clock seconds]
                      {Version information not maintained for this page}]]
      }
    }

    # Determine the number of the most recent version

    set results [list]
    set mostRecent [mk::view size $db.pages!$id.changes]

    # List the most recent version if requested

    if {$start == 0} {
      pagevarsDB $db $id date who
      lappend results [list $mostRecent $date $who]
      incr start
    }

    # Do earlier versions as needed

    set idx [expr {$mostRecent - $start}]
    while {$idx >= 0 && [llength $results] < $limit} {
      foreach {date who} [mk::get $db.pages!$id.changes!$idx date who] break
      lappend results [list $idx $date $who]
      incr idx -1
    }

    return $results
  }

  #----------------------------------------------------------------------------
  #
  # GetPageVersion --
  #
  #     Retrieves a historic version of a page from the database.
  #
  # Parameters:
  #     id - Row ID in the 'pages' view of the page being queried.
  #     version - Version number that is to be retrieved (row ID in
  #               the 'changes' subview)
  #	db - Handle to the database where the Wiki is stored.
  #
  # Results:
  #     Returns page text as Wikitext. Throws an error if the version
  #     is non-numeric or out of range.
  #
  #----------------------------------------------------------------------------

  proc GetPageVersion {id {version {}} {db wdb}} {
    return [join [GetPageVersionLines $id $version $db] \n]
  }
  proc GetPageVersionLines {id {version {}} {db wdb}} {
    set page [mk::get $db.pages!$id page]
    set latest [mk::view size $db.pages!$id.changes]
    if {$version eq {}} {
      set version $latest
    }
    if {![string is integer $version] || $version < 0} {
      return -code error "bad version number \"$version\":\
                          must be a positive integer" \
        -errorcode {wiki badVersion}
    }
    if {$version > $latest} {
      return -code error "cannot get version $version, latest is $latest" \
        -errorcode {wiki badVersion}
    }
    if {$version == $latest} {
      return [split $page \n]
    }
    set v $latest
    set lines [split $page \n]
    while {$v > $version} {
      incr v -1
      set i [expr {[mk::view size $db.pages!$id.changes!$v.diffs]}]
      while {$i > 0} {
        incr i -1
        foreach {from to old} \
          [mk::get $db.pages!$id.changes!$v.diffs!$i from to old] \
          break
        if {$from <= $to} {
          set lines [eval [linsert $old 0 \
                             lreplace $lines[set lines {}] $from $to]]
        } else {
          set lines [eval [linsert $old 0 \
                             linsert $lines[set lines {}] $from]]
        }
      }
    }
    return $lines
  }

  #----------------------------------------------------------------------------
  #
  # AnnotatePageVersion --
  #
  #     Retrieves a version of a page in the database, annotated with
  #     information about when changes appeared.
  #
  # Parameters:
  #	id - Row ID in the 'pages' view of the page to be annotated
  #	version - Version of the page to annotate.  Default is the current
  #               version
  #	db - Handle to the Wikit database.
  #
  # Results:
  #	Returns a list of lists. The first element of each sublist is a line
  #	from the page.  The second element is the number of the version
  #     in which that line first appeared. The third is the time at which
  #     the change was made, and the fourth is a string identifying who
  #     made the change.
  #
  #----------------------------------------------------------------------------

  proc AnnotatePageVersion {id {version {}} {db wdb}} {
    set latest [mk::view size $db.pages!$id.changes]
    if {$version eq {}} {
      set version $latest
    }
    if {![string is integer $version] || $version < 0} {
      return -code error "bad version number \"$version\":\
                          must be a positive integer" \
        -errorcode {wiki badVersion}
    }
    if {$version > $latest} {
      return -code error "cannot get version $version, latest is $latest" \
        -errorcode {wiki badVersion}
    }

    # Retrieve the version to be annotated

    set lines [GetPageVersionLines $id $version $db]

    # Start the annotation by guessing that all lines have been there since
    # the first commit of the page.

    if {$version == $latest} {
      pagevarsDB $db $id date who
    } else {
      foreach {date who} [mk::get $db.pages!$id.changes!$version date who] \
        break
    }
    if {$latest == 0} {
      set firstdate $date
      set firstwho $who
    } else {
      foreach {firstdate firstwho} [mk::get $db.pages!$id.changes!0 date who] \
        break
    }

    # versions has one entry for each element in $lines, and contains
    # the version in which that line first appeared.  We guess version
    # 0 for everything, and then fill in later versions by working backward
    # through the diffs.  Similarly 'dates' has the version dates and
    # 'whos' has the users that committed the versions.
    set versions [struct::list repeat [llength $lines] 0]
    set dates [struct::list repeat [llength $lines] $date]
    set whos [struct::list repeat [llength $lines] $who]

    # whither contains, for each line a version being examined, the line
    # index corresponding to that line in 'lines' and 'versions'. An index
    # of -1 indicates that the version being examined is older than the
    # line
    set whither [list]
    for {set i 0} {$i < [llength $lines]} {incr i} {
      lappend whither $i
    }

    # Walk backward through all versions of the page
    while {$version > 0} {
      incr version -1


      # Walk backward through all changes applied to a version
      set i [expr {[mk::view size $db.pages!$id.changes!$version.diffs]}]
      foreach {lastdate lastwho} \
        [mk::get $db.pages!$id.changes!$version date who] \
        break
      while {$i > 0} {
        incr i -1
        foreach {from to old} \
          [mk::get $db.pages!$id.changes!$version.diffs!$i from to old] \
          break

        # Update 'versions' for all lines that first appeared in the
        # version following the one being examined

        for {set j $from} {$j <= $to} {incr j} {
          set w [lindex $whither $j]
          if {$w > 0} {
            lset versions $w [expr {$version + 1}]
            lset dates $w $date
            lset whos $w $who
          }
        }

        # Update 'whither' to preserve correspondence between the version
        # being examined and the one being annotated.  Lines that do
        # not exist in the annotated version are marked with -1.

        if {[llength $old] == 0} {
          set m1s {}
        } else {
          set m1s [struct::list repeat [llength $old] -1]
        }
        if {$from <= $to} {
          set whither [eval [linsert $m1s 0 \
                               lreplace $whither[set whither {}] $from $to]]
        } else {
          set whither [eval [linsert $m1s 0 \
                               linsert $whither[set whither {}] $from]]
        }
      }
      set date $lastdate
      set who $lastwho
    }
    set result {}
    foreach line $lines v $versions date $dates who $whos {
      lappend result [list $line $v $date $who]
    }
    return $result
  }

  # addRefs - a newly created page $id contains $refs references to other pages
  # Add these references to the .ref view.
  proc addRefs {id db refs} {
    if {$id != 2 && $id != 4} {
      foreach x $refs {
        if {$id != $x} {
          mk::row append $db.refs from $id to $x
        }
      }
    }
  }

  # delRefs - remove all references from page $id to anywhere
  proc delRefs {id db} {
    set v [mk::select $db.refs from $id]	;# the set of all references from $id

    # delete from last to first
    set n [llength $v]
    while {[incr n -1] >= 0} {
      mk::row delete $db.refs![lindex $v $n]
    }
  }

  # FixPageRefs - recreate the entire refs view
  proc FixPageRefs {{db wdb}} {
    mk::view size $db.refs 0	;# delete all contents from the .refs view

    # visit each page, recreating its refs
    mk::loop c $db.pages {
      set id [mk::cursor position c]
      pagevarsDB $db $id date page
      if {$date != 0} {
        # add the references from page $id to .refs view
        addRefs $id $db [StreamToRefs [TextToStream $page] [list ::Wikit::InfoProc $db]]
      }
    }
    DoCommit
  }

  # Helper to 'SavePage'. Changes all references to page 'name'
  # contained in the 'text' into references to page 'newName'. This is
  # performed if a page changes its title, to keep all internal
  # references in sync. Only pages which are known to refer to the
  # changed page (see 'SavePage') are modified.

  proc replaceLink {text old new} {
    # this code is not fullproof, it misses links in keyword lists
    # this means page renames are not 100% accurate (but refs still are)

    set newText ""
    foreach line [split $text \n] {
      # don't touch quoted lines, except if its a list item
      if {![regexp "^\[ \t\]\[^\\*0-9\]" $line] ||
          [regexp "^(   |\t)\[ \t\]*(\\*|\[0-9\]\\.) " $line]} {
        #23nov02 jcw: this failed on title contents such as C++
        #regsub -all -nocase "\\\[$old\\\]" $line "\[$new\]" line
        set line [string map [list "\[$old\]" "\[$new\]"] $line]
      }
      lappend newText $line
    }
    join $newText \n
  }

  # SavePageDB - store page $id ($who, $text, $newdate)
  proc SavePageDB {db id text newWho newName {newdate ""} {commit 1}} {
    set changed 0

    variable mutex;
    if {$mutex ne ""} {
      ::thread::mutex lock $mutex	;# lock for update
    }
    if {[catch {
      pagevarsDB $db $id name date page who

      if {$newName != $name} {
        set changed 1

        # rewrite all pages referencing $id changing old name to new
        # Special case: If the name is being removed, leave references intact;
        # this is used to clean up duplicates.
        if {$newName != ""} {
          foreach x [mk::select $db.refs to $id] {
            set x [mk::get $db.refs!$x from]
            set y [mk::get $db.pages!$x page]
            mk::set $db.pages!$x page [replaceLink $y $name $newName]
          }

          # don't forget to adjust links in this page itself
          set text [replaceLink $text $name $newName]
        }

        AdjustTitleCache $name $newName $id
        mk::set $db.pages!$id name $newName
      }

      if {$newdate != ""} {
        # change the date if requested
        mk::set $db.pages!$id date $newdate
      }

      # avoid creating a log entry and committing if nothing changed
      set text [string trimright $text]
      if {$changed || $text != $page} {
        # make sure it parses before deleting old references
        set newRefs [StreamToRefs [TextToStream $text] [list ::Wikit::InfoProc $db]]
        delRefs $id $db
        addRefs $id $db $newRefs

        if {$id == 3} {
          catch { gButton::modify Help -text [lindex [Wikit::GetTitle 3] 0] }
        }

        # If this isn't the first time that the given page has been stored
        # in the databse, make a change log entry for rollback.

        mk::set $db.pages!$id page $text who $newWho
        if {$page ne {} || [mk::view size $db.pages!$id.changes]} {
          UpdateChangeLog $db $id $name $date $who $page $text
        }

        if {$newdate == ""} {
          mk::set $db.pages!$id date [clock seconds]
          set commit 1
        }

      }
    } r]} {
      Debug.error "SavePageDb: '$r'"
    }

    if {$commit} {
      AddLogEntry $id $db
      DoCommit $db
    }

    if {$mutex ne ""} {
      ::thread::mutex unlock $mutex	;# unlock for db update
    }
  }

  #----------------------------------------------------------------------------
  #
  # UpdateChangeLog --
  #     Updates the change log of a page.
  #
  # Parameters:
  #	db - Handle to the Wiki database
  #     id - Row ID in the 'pages' view of the page being updated
  #     name - Name that the page had *before* the current version.
  #     date - Date of the last update of the page *prior* to the one
  #            being saved.
  #     who - String identifying the user that updated the page last
  #           *prior* to the version being saved.
  #     page - Previous version of the page text
  #     text - Version of the page text now being saved.
  #
  # Results:
  #	None
  #
  # Side effects:
  #	Updates the 'changes' view with the differences that recnstruct
  #     the previous version from the current one.
  #
  #----------------------------------------------------------------------------

  proc UpdateChangeLog {db id name date who page text} {

    # Store summary information about the change
    set version [mk::view size $db.pages!$id.changes]
    mk::row append $db.pages!$id.changes date $date who $who

    # Determine the changed lines
    set linesnew [split $text \n]
    set linesold [split $page \n]
    set lcs [::struct::list longestCommonSubsequence2 $linesnew $linesold 5]
    set changes [::struct::list lcsInvert \
                   $lcs [llength $linesnew] [llength $linesold]]

    # Store change information in the database
    set i 0
    set change 0	;# record magnitude of change
    foreach tuple $changes {
      foreach {action newrange oldrange} $tuple break
      switch -exact -- $action {
        deleted {
          foreach {from to} $newrange break
          set old {}

          incr change [string length [lrange $linesnew $from $to]]
        }
        added  {
          foreach {to from} $newrange break
          foreach {oldfrom oldto} $oldrange break
          set old [lrange $linesold $oldfrom $oldto]

          incr change [expr {abs([string length [lrange $linesnew $from $to]] - [string length [lrange $linesold $oldfrom $oldto]])}]
        }
        changed  {
          foreach {from to} $newrange break
          foreach {oldfrom oldto} $oldrange break
          set old [lrange $linesold $oldfrom $oldto]

          incr change [expr {abs([string length [lrange $linesnew $from $to]] - [string length [lrange $linesold $oldfrom $oldto]])}]
        }
      }
      mk::row append $db.pages!$id.changes!$version.diffs \
        from $from to $to old $old
      incr i
    }
    mk::row set $db.pages!$id.changes!$version delta $change	;# record magnitude of changes
  }

  # SavePage - store page $id ($who, $text, $newdate)
  proc SavePage {id text who newName {newdate ""}} {
    return [SavePageDB wdb $id $text $who $newName $newdate]
  }

  # DoCommit - commit changes to the database
  proc DoCommit {{db wdb}} {
    mk::file commit $db
  }

  # DoSync - sync Wikit to the contents of a URL
  proc DoSync {url {db wdb}} {
    puts "Looking for changes at $url ..."
    package require http
    package require autoproxy
    autoproxy::init
    set re \
      "^Title:\\s+(\[^\n]+)\nDate:\\s+(\[^\n]+)\nSite:\\s+(\[^\n]+)\n\n(.*)"
    set index [graburl $url/index]
    if {[regexp {^0 \d+ \d+} $index]} {
      set i 0
      foreach {xpage xvers xdate} $index {
        if {$xpage >= [mk::view size $db.pages]} {
          mk::view size $db.pages [expr {$xpage+1}]
        }
        pagevarsDB $db $xpage date
        if {$date != $xdate} {
          puts -nonewline [format %6d $xpage]
          flush stdout
          set page [graburl $url/$xpage]
          if {[regexp $re $page - t d s p]} {
            puts "  $t - $d"
            SavePageDB $db $xpage $p $s $t $xdate
            if {[incr i] % 10 == 0} { DoCommit $db }
          } else {
            puts ?
          }
        }
      }
      DoCommit $db
      puts "Update done."
    } else {
      puts "No suitable index found, update ignored."
    }
  }
}

### Local Variables: ***
### mode:tcl ***
### tcl-indent-level:2 ***
### tcl-continued-indent-level:2 ***
### indent-tabs-mode:nil ***
### End: ***
