# format.tcl -- Formatter for wiki markup text, CGI as well as GUI
# originally written by Jean-Claude Wippler, 2000..2007 - may be used freely

package provide WFormat 1.1

namespace eval ::WFormat {
  namespace export TextToStream StreamToTcl StreamToHTML StreamToRefs \
    StreamToUrls Expand_HTML FormatWikiToc ShowDiffs

  # In this file:
  #
  # proc TextToStream {text} -> stream
  # proc StreamToHTML {stream cgiPrefix infoProc} -> {{html} {urls}}
  # proc StreamToRefs {stream infoProc} -> {pageNum ...}
  # proc StreamToUrls {stream} -> {url type ...}
  #
  # The "Text"   format is a Wiki-like one you can edit with a text editor.
  # The "Tk"     format can insert styled text information in a text widget.
  # The "HTML"   format is the format generated for display by a browser.
  # The "Refs"   format is a list with details about embedded references.
  # The "Urls"   format is a list of external references, bracketed or not.
  # The "Stream" format is a Tcl list, it's only used as interim format.

  # =========================================================================

  ### More format documentation

  # =========================================================================

  #
  # Ad "Tk")     This is a list of pairs {text taglist text taglist ...}
  #              which can be directly inserted into any text widget.
  #
  # Ad "Stream") This is the first time that the stream format is documented.
  #
  #     The base format is that of a list of pairs {cmd arg cmd arg ...}
  #     The available commands fall into three categories [x]:
  #
  #     1. Data carriers
  #     2. Visual markers
  #     3. Structural markers
  #
  #     [x] In the previous incarnation of this stream format the categories
  #         were essentially all mixed up and jumbled together. For example
  #         the command 'T' crossed category 1 and 3, introducing a new para-
  #         graph and also carrying the first fragment of text of said para-
  #         graph. That made for difficult creation and difficult interpreta-
  #         tion. It is the separation of the categories which makes the re-
  #         organized format much easier to generate and convert (<=> simpler
  #         code, which is even faster). (Not to mention the eviction of
  #         treating [, ], {, }, and \ as special characters. They are not).
  #
  #     Ad 1)   The empty string and 'g', 'u' and 'x'. The first is for text,
  #             the others specify the various possible links.
  #
  #             Cmd	Argument
  #             ------------------------------------------------------
  #             {}	The text to display
  #             g	Name/Title of referenced wiki page
  #             u	external URL, was unbracket'ed in sources
  #             x	external URL, bracket'ed in sources
  #             ------------------------------------------------------
  #
  #     Ad 2)   Currently only two: 'b' and 'i' for bold and italic emphasis.
  #             The argument specifies if the emphasis is switched on or off.
  #             The permitted values are 0 (off) and 1 (on).
  #
  #     Ad 3)   These are the markers for the various distinctive sections
  #             in wiki markup.
  #
  #             Cmd	'Begin' 			Argument
  #             ------------------------------------------------------
  #             T	Paragraph				Nesting level
  #             Q	Quoted line				Nesting level
  #             U	List item (unordered)	Nesting level
  #             O	List item (enumerated)	Nesting level
  #             I	List item (term)		Nesting level
  #             D	List item (term def)	Nesting level
  #             H	Horizontal rule			Line-width
  #			  C code lines
  #             ------------------------------------------------------
  #
  #             Note: The current frontend renderer provides only nesting
  #                   level 0 and a line-width 1. The current backend
  #                   renderers ignore this information.
  #

  # =========================================================================
  # =========================================================================

  ### Frontend renderer                         :: Wiki Markup ==> Stream ###

  # =========================================================================
  # =========================================================================

  ## Basic operation: Each line is classified via regexes and then handled
  ## according to its type. Text lines are coalesced into paragraphs, with
  ## some special code to deal with the boundary between normal text and
  ## verbatim quoted text. Each collected line is then separated into chunks
  ## of text, highlighting command and links (wiki page / external). This is
  ## then added to the internal representation.

  proc TextToStream {text {fixed 0} {code 0} {do_rlinks 1}} {
    # Based upon ideas from the kiwi renderer. One step rendering into
    # the internal representation without a script as intermediate step.

    set irep      [list]  ; # Internal representation generated here.
    set paragraph ""      ; # Buffer for the text of a single paragraph
    set empty_std 0       ; # boolean - set if the preceding line was empty
    set mode_fixed $fixed ; # flag to indicate currently in fixed font block
    set mode_code $code   ; # indicates code block (no markup)
    set mode_option 0	  ; # options (fixed option, variable description)
    set optnum 0	 	  ; # option block number
    set optlen 0	 	  ; # length of option block fixed part
    foreach line [split $text \n] {
      # Per line, classify the it and extract the main textual information.
      foreach {tag depth txt aux} [linetype $line] break ; # lassign
      set otag $tag
      if {$mode_fixed && $tag ne "FIXED" && $tag ne "CODE" \
            && $tag ne "EVAL"} {
        # if already in fixed mode, then line must be fixed
        # or code content, or eval output
        set tag FIXED_CONTENT
      }
      if {$mode_option && $tag ne "OPTION"} {
        set tag OPTION_CONTENT
      }
      # Classification tags
      #
      # UL, OL, DL = Lists (unordered/bullet, ordered/enum,
      #                     definition/itemized)
      # PRE        = Verbatim / Quoted lines
      # HR         = Horizontal rule
      # STD        = Standard text
      # CODE		 = fixed font, no markup
      # FIXED		 = fixed font, markup
      # OPTION	 = start/end of option list

      ## Whenever we encounter a special line, not quoted, any
      ## preceding empty line has no further effect.
      #

      switch -exact -- $tag {
        HR - 1UL - 2UL - 3UL - 4UL - 5UL - 1OL - 2OL - 3OL - 4OL - 5OL - DL {set empty_std 0}
        default {}
      }

      ## Whenever we encounter a special line, including quoted, we
      ## have to render the data of the preceding paragraph, if
      ## there is any.
      #
      switch -exact -- $tag {
        HR - 1UL - 2UL - 3UL - 4UL - 5UL - 1OL - 2OL - 3OL - 4OL - 5OL - DL - PRE - TBL - CTBL - TBLH - HD2 - HD3 - HD4 - BLAME_START - BLAME_END - CENTERED - BACKREFS - CATEGORY - INLINETOC {
          if {$paragraph != {}} {
            if {$mode_fixed} {
              lappend irep FI {}
              set paragraph [join $paragraph \n]
              if {$mode_code} {
                lappend irep {} $paragraph
              } else {
                render $paragraph
              }
              lappend irep FE {}
            } else {
              lappend irep T 0 ; render $paragraph
              set paragraph ""
            }
          }
        }
        default {}
      }

      ## Now processs the lines according to their types.
      #
      # Tag   | depth         | txt             | pfx           | aux
      # ------+---------------+-----------------+---------------+---------
      # UL    | nesting level | text of item    | before bullet | bullet
      # OL    | nesting level | text of item    | before bullet | bullet
      # DL    | nesting level | term definition | before bullet | term
      # PRE   | 1             | text to display |
      # HR    | 0             | text of ruler   |
      # STD   | 0             | text to display |
      # FIXED | 1			 	| text to display |
      # CODE  | 1			 	| text to display |
      # ------+---------------+-----------------+---------------+---------

      # HR     - Trivial
      # UL, OL - Mark their beginning and then render their text
      #        - like a normal paragraph.
      # DL     - Like list item, except that there are two different
      #          parts of text we have to render, term and term definition
      # PRE    - Quoted text is searched for links, but nothing
      #          more. An empty preceding line is added to the
      #          quoted section to keep it at a distance from the
      #          normal text coming before.
      # STD    - Lines are added to the paragraph until an empty one is
      #          encountered. This closes the paragraph.
      # CODE	 - fixed font - no markup
      # FIXED  - like CODE, but markup respected

      switch -exact -- $tag {
        HR  {lappend irep H 1}
        1UL {lappend irep 1U 0 ; render $txt}
        2UL {lappend irep 2U 0 ; render $txt}
        3UL {lappend irep 3U 0 ; render $txt}
        4UL {lappend irep 4U 0 ; render $txt}
        5UL {lappend irep 5U 0 ; render $txt}
        1OL {lappend irep 1O 0 ; render $txt}
        2OL {lappend irep 2O 0 ; render $txt}
        3OL {lappend irep 3O 0 ; render $txt}
        4OL {lappend irep 4O 0 ; render $txt}
        5OL {lappend irep 5O 0 ; render $txt}
        DL  {
          lappend irep I 0 ; render $aux
          lappend irep D 0 ; render $txt
        }
        HD2 {
          lappend irep $tag 0 ; render [string range $txt 2 end-2] ; lappend irep HDE 0
        }
        HD3 {
          lappend irep $tag 0 ; render [string range $txt 3 end-3] ; lappend irep HDE 0
        }
        HD4 {
          lappend irep $tag 0 ; render [string range $txt 4 end-4] ; lappend irep HDE 0
        }
        PRE {
          # Transform a preceding 'STD {}' into an empty Q line,
          # i.e make it part of the verbatim section, enforce
          # visual distance.

          if {$empty_std} {lappend irep Q 0 {} {}; set empty_std 0}
          lappend irep Q 0
          if {$txt != {}} {
            if {$do_rlinks} {
              rlinks $txt
            } else {
              lappend irep {} $txt
            }
          }
        }
        STD {
          if {$txt == {}} {
            if {$paragraph != {}} {
              lappend irep T 0 ; render $paragraph
              set paragraph ""
            }
            set empty_std 1
          } else {
            if {$paragraph != {}} {append paragraph " "}
            append paragraph $txt
            set empty_std 0
          }
        }
        CODE -
        FIXED {
          if {$tag eq "CODE"} {
            set mode_code 1
          } else {
            set mode_code 0
          }
          if {$mode_fixed} {
            if {$paragraph ne {}} {
              set paragraph [join $paragraph \n]
              lappend irep FI {}
              if {$mode_code} {
                lappend irep {} $paragraph
              } else {
                render $paragraph
              }
              lappend irep FE {}
            }
            set mode_fixed 0
          } else {
            if {$paragraph ne ""} {
              lappend irep T 0
              render $paragraph
            }
            set mode_fixed 1
            if {$empty_std} {
              lappend irep C 0 {} {}
              set empty_std 0
            }
            lappend irep C 0
          }
          set paragraph {}
        }
        FIXED_CONTENT {
          if { $otag eq "BLAME_START" } {
            if {$paragraph ne {}} {
              set paragraph [join $paragraph \n]
              lappend irep FI {}
              if {$mode_code} {
                lappend irep {} $paragraph
              } else {
                render $paragraph
              }
              lappend irep FE {}
            }
            set paragraph {}
            lappend irep BLS [string range $line 6 end]
          } elseif { $otag eq "BLAME_END" } { 
            if {$paragraph ne {}} {
              set paragraph [join $paragraph \n]
              lappend irep FI {}
              if {$mode_code} {
                lappend irep {} $paragraph
              } else {
                render $paragraph
              }
              lappend irep FE {}
            }
            set paragraph {}
            lappend irep BLE 0
          } else {
            lappend paragraph $line
          }
        }
        OPTION {
          if {$mode_option} {
            # end option list and record max length of fixed part
            lappend irep L "$optnum $optlen"
            set mode_option 0
            set optlen 0
          } else {
            # start new option list
            if {$empty_std} {
              lappend irep C 0 {} {}
              set empty_std 0
            }
            if {$paragraph ne ""} {
              lappend irep T 0
              render $paragraph
              set paragraph ""
            }
            set mode_option 1
            set optlen 0
            lappend irep L [incr optnum]
          }
        }
        OPTION_CONTENT {
          if { $otag eq "BLAME_START" || $otag eq "BLAME_END"} {
            lappend irep L "$optnum $optlen"
            set mode_option 0
            set optlen 0
            if { $otag eq "BLAME_START" } { 
              lappend irep BLS [string range $line 6 end]
            } else {
              lappend irep BLE 0
            }
            # start new option list
            if {$empty_std} {
              lappend irep C 0 {} {}
              set empty_std 0
            }
            if {$paragraph ne ""} {
              lappend irep T 0
              render $paragraph
              set paragraph ""
            }
            set mode_option 1
            set optlen 0
            lappend irep L [incr optnum]
          } else {
            # the fixed part should be followed by one or more tabs
            # - if not then fall back to using the first double-space
            #   then the first space
            if {[regexp {^\s*(.+?)\t\s*(.*)$} $txt - opt rest]
                || [regexp {^\s*(.+?)\s{2,}(.*)$} $txt - opt rest]
                || [regexp {^\s*(.+?)\s+(.*)$} $txt - opt rest]
              } {
              set opt [string trim $opt]
              regsub -all \t $rest \s rest
              lappend irep F 0
              set optlen [max $optlen [render $opt]]
              lappend irep V \t
              render $rest V
            } elseif {$txt eq ""} {
              lappend irep F 0
            }
          }
        }
        EVAL {
          if {![interp exists eval_interp]} {
            # create an intepreter to run eval commands
            # when running via web/ GGI this should be a safe interp
            interp create -safe eval_interp
            # create the wikidir variable as a convenience
            if {[catch {
              file dirname $Wikit::wikifile
            } wikidir]} {
              set wikidir ""
            } else {
              set wikidir [file normalize $wikidir]
              eval_interp eval [list set wikidir $wikidir]

              # set auto_path in the interp to look for packages
              # in common places

              # lib directory next to dir containing the wiki
              set lib [file join [file dirname $wikidir] lib]
              if {[file isdirectory $lib]} {
                eval_interp eval [list lappend auto_path $lib]
              }

              # starkit.vfs/lib
              if {[info exists starkit::topdir]} {
                set lib [file join $starkit::topdir lib]
                if {[file isdirectory $lib]} {
                  eval_interp eval [list lappend auto_path $lib]
                }
              }
            }
          }
          # people might feel more comfortable putting quotes or
          # brackets around page references - so just strip them off
          set name [string trim $txt "'\"\[\]"] ;# "
          set id [WDB LookupPage $name]
          set page [WDB GetContent $id]
          # delete any code markup in the page (this allows the
          # page to be displayed as code markup but still be run)
          regsub -all {(^======\n|\n======\n|\n======$)} $page {} page
          if {[catch {set txt [eval_interp eval $page]} msg]} {
            lappend irep i 1
            lappend irep "" "Error evaluating $txt:"
            lappend irep i 0
            lappend irep C 0
            lappend irep "" $msg
          } else {
            if {$mode_fixed} {
              if {$paragraph ne ""} {
                if {$mode_code} {
                  lappend irep {} $paragraph
                } else {
                  render $paragraph
                }
                set paragraph ""
              }
              lappend irep X 1
              set irep [concat $irep \
                          [TextToStream $txt $mode_fixed $mode_code]]
              lappend irep X 0
            } else {
              append paragraph " $txt"
            }
          }
        }
        TBLH {
          lappend irep TRH 0
          set txt [string map {%|% %!url_name_delimiter_pipe!%} $txt]
          foreach te [lrange [split [string range $txt 1 end-1] "|"] 1 end-1] {
            lappend irep TDH 0 ; render [string map {%!url_name_delimiter_pipe!% %|%} $te] ; lappend irep TDEH 0
          }
        }
        CTBL {
          lappend irep CTR 0
          set txt [string map {%|% %!url_name_delimiter_pipe!%} $txt]
          foreach te [lrange [split [string range $txt 1 end-1] "|"] 1 end-1] {
            lappend irep TD 0 ; render [string map {%!url_name_delimiter_pipe!% %|%} $te] ; lappend irep TDE 0
          }
        }
        TBL {
          lappend irep TR 0
          set txt [string map {%|% %!url_name_delimiter_pipe!%} $txt]
          foreach te [lrange [split $txt "|"] 1 end-1] {
            lappend irep TD 0 ; render [string map {%!url_name_delimiter_pipe!% %|%} $te] ; lappend irep TDE 0
          }
        }
        BLAME_START {
          lappend irep BLS $txt
        }
        BLAME_END {
          lappend irep BLE 0
        }
        CENTERED {
          lappend irep CT 0
        }
        INLINETOC {
          lappend irep INLINETOC 0
        }
        BACKREFS {
          lappend irep BACKREFS $txt
        }
        CATEGORY {
          lappend irep CATEGORY $txt
        }
        default {
          error "Unknown linetype $tag"
        }
      }
    }

    # Render the last paragraph, if any.

    if {$paragraph != {}} {
      if {$mode_fixed} {
        lappend irep FI {}
        set paragraph [join $paragraph \n]
        if {$mode_code} {
          lappend irep {} $paragraph
        } else {
          render $paragraph
        }
        lappend irep FE {}
      } else {
        lappend irep T 0
        render $paragraph
      }
    }
    return $irep
  }

  # returns the largest of two integers
  proc max {a b} {expr {$a > $b ? $a : $b}}

  proc linetype {line} {
    # Categorize a line of wiki text based on indentation and prefix

    set line [string trimright $line]

    ## Compat: retain tabs ...
    ## regsub -all "\t" $line "    " line
    #
    ## More compat'ibility ...
    ## The list tags allow non-multiples of 3 if the prefix contains at
    ## least 3 spaces. The standard wiki accepts anything beyond 3 spaces.
    ## Keep the kiwi regexes around for future enhancements.

    foreach {tag re} {
      1UL	{^(   + {0,2})(\*) (\S.*)$}
      2UL	{^(   + {0,2})(\*\*) (\S.*)$}
      3UL	{^(   + {0,2})(\*\*\*) (\S.*)$}
      4UL	{^(   + {0,2})(\*\*\*\*) (\S.*)$}
      5UL	{^(   + {0,2})(\*\*\*\*\*) (\S.*)$}
      1OL	{^(   + {0,2})(\d)\. (\S.*)$}
      2OL       {^(   + {0,2})(\d\d)\. (\S.*)$}
      3OL       {^(   + {0,2})(\d\d\d)\. (\S.*)$}
      4OL       {^(   + {0,2})(\d\d\d\d)\. (\S.*)$}
      5OL       {^(   + {0,2})(\d\d\d\d\d)\. (\S.*)$}
      DL	{^(   + {0,2})([^:]+):   (\S.*)$}

      1UL	{^(   +)(\*) (\S.*)$}
      1OL	{^(   +)(\d)\. (\S.*)$}
      DL	{^(   +)([^:]+):   (\S.*)$}

      FIXED  {^()()(===)$}
      CODE   {^()()(======)$}
      OPTION {^()()(\+\+\+)$}
      #EVAL {^(\+eval)(\s?)(.+)$}
      BLAME_START {^(>>>>>>)(\s?)(.+)$}
      BLAME_END   {^(<<<<<<)$}
      CENTERED {^()()(!!!!!!)$}
      BACKREFS {^(<<backrefs>>)()(.*)$}
      BACKREFS {^(<<backrefs:)()(.*)>>$}
      INLINETOC {^<<TOC>>$}
      CATEGORY {^(<<categories>>)()(.*)$}
    } {
      # Compat: Remove restriction to multiples of 3 spaces.
      if {[regexp $re $line - pfx aux txt]} {
        #    && string length $pfx % 3 == 0
        return [list $tag [expr {[string length $pfx]/3}] $txt $aux]
      }
    }

    foreach {tag re} {
      HD4    {^(\*\*\*\*.+\*\*\*\*)$}
      HD3    {^(\*\*\*.+\*\*\*)$}
      HD2    {^(\*\*.+\*\*)$}

    } {
      if {[regexp $re $line - txt]} {
        return [list $tag 0 $txt]
      }
    }

    # PO	{^\+-\S+([^\S]+)\S+(\S.*)$}

    # Compat: Accept a leading TAB is marker for quoted text too.

    if {([string index $line 0] == " ") || ([string index $line 0] == "\t")} {
      return [list PRE 1 $line]
    }
    if {[regexp {^-{4,}$} $line]} {
      return [list HR 0 $line]
    }
    if {[string match "%|*|%" $line]} {
      return [list TBLH 0 $line]
    }
    if {[string match "&|*|&" $line]} {
      return [list CTBL 0 $line]
    }
    if {[string match "|*|" $line]} {
      return [list TBL 0 $line]
    }
    return [list STD 0 $line]
  }

  proc rlinks {text} {
    # Convert everything which looks like a link into a link. This
    # command is called for quoted lines, and only quoted lines.

    upvar irep irep

    # Compat: (Bugfix) Added " to the regexp as proper boundary of an url.
    #set re {\m(https?|ftp|news|mailto|file):(\S+[^\]\)\s\.,!\?;:'>"])}
    #set re {\m(https?|ftp|news|mailto|file):([^\s:]+[^\]\)\s\.,!\?;:'>"])}
    set re {\m(https?|ftp|news|mailto|file):([^\s:]\S*[^\]\)\s\.,!\?;:'>"])} ;#"
    set txt 0
    set end [string length $text]

    ## Find the places where an url is inside of the quoted text.

    foreach {match dummy dummy} [regexp -all -indices -inline $re $text] {
      # Skip the inner matches of the RE.
      foreach {a e} $match break
      if {$a > $txt} {
        # Render text which was before the url
        lappend irep {} [string range $text $txt [expr {$a - 1}]]
      }
      # Render the url
      lappend irep u [string range $text $a $e]
      set txt [incr e]
    }
    if {$txt < $end} {
      # Render text after the last url
      lappend irep {} [string range $text $txt end]
    }
    return
  }

  proc render {text {mode ""}} {
    # Rendering of regular text: links, markup, brackets.

    # The main idea/concept behind the code below is to find the
    # special features in the text and to isolate them from the normal
    # text through special markers (\0\1...\0). As none of the regular
    # expressions will match across these markers later passes
    # preserve the results of the preceding passes. At the end the
    # string is split at the markers and then forms the list to add to
    # the internal representation. This way of doing things keeps the
    # difficult stuff at the C-level and avoids to have to repeatedly
    # match and process parts of the string.

    upvar irep irep
    variable codemap

    ## puts stderr \]>>$irep<<\[
    ## puts stderr >>>$text<<<

    # Detect page references, external links, bracketed external
    # links, brackets and markup (hilites).

    # Complex RE's used to process the string
    set pre  {\[([^\]]*)]}  ; #  page references ; # compat
    set bpre  {\[(brefs:|backrefs:)([^\]]*)]}  ; #  page back-references ; # compat
    #set lre  {\m(https?|ftp|news|mailto|file):(\S+[^\]\)\s\.,!\?;:'>"])} ; # "
    #set lre  {\m(https?|ftp|news|mailto|file):([^\s:]+[^\]\)\s\.,!\?;:'>"])} ; # "
    set prelre {\[\m(https?|ftp|news|mailto|file):([^\s:\]][^\]]*?)]} ; # "
    set lre  {\m(https?|ftp|news|mailto|file):([^\s:]\S*[^\]\)\s\.,!\?;:'>"])} ; # "
    set lre2 {\m(https?|ftp|news|mailto|file):([^\s:]\S*[^\]\)\s\.,!\?;:'>"]%\|%[^%]+%\|%)} ; # "

#    set blre "\\\[\0\1u\2(\[^\0\]*)\0\\\]"

                                                 # Order of operation:
                                                 # - Remap double brackets to avoid their interference.
                                                 # - Detect embedded links to external locations.
                                                 # - Detect brackets links to external locations (This uses the
                                                 #   fact that such links are already specially marked to make it
                                                 #   easier.
                                                 # - Detect references to other wiki pages.
                                                 # - Render bold and italic markup.
                                                 #
                                                 # Wiki pages are done last because there is a little conflict in
                                                 # the RE's for links and pages: Both allow usage of the colon (:).
                                                 # Doing pages first would render links to external locations
                                                 # incorrectly.
                                                 #
                                                 # Note: The kiwi renderer had the order reversed, but also
                                                 # disallowed colon in page titles. Which is in conflict with
                                                 # existing wiki pages which already use that character in titles
                                                 # (f.e. [COMPANY: Oracle].

                                                 # Make sure that double brackets do not interfere with the
                                                 # detection of links.
                                                 regsub -all {\[\[} $text {\&!} text

                                                 ## puts stderr A>>$text<<*

                                                 # Isolate external links.
                                                 regsub -all $prelre $text "\0\1x\2\\1\3\\2\0" text
                                                 ## puts stderr X>>$text<<*
                                                 regsub -all $lre2 $text "\0\1u\2\\1\3\\2\0" text
                                                 regsub -all $lre  $text "\0\1u\2\\1\3\\2\0" text
                                                 set text [string map {\3 :} $text]
                                                 ## puts stderr C>>$text<<*

                                                 # External links in brackets are simpler cause we know where the
                                                 # links are already.
#                                                 regsub -all $blre $text "\0\1x\2\\1\0" text
                                                 ## puts stderr D>>$text<<*

                                                 # Now handle wiki page (back) references
                                                 regsub -all $bpre $text "\0\1G\2\\2\0" text
                                                 regsub -all $pre $text "\0\1g\2\\1\0" text
                                                 ## puts stderr B>>$text<<*

                                                 # Hilites are transformed into on and off directives.
                                                 # This is a bit more complicated ... Hilites can be written
                                                 # together and possible nested once, so it has make sure that
                                                 # it recognizes everything in the correct order!

                                                 # Examples ...
                                                 # {''italic'''''bold'''}         {} {<i>italic</i><b>bold</b>}
                                                 # {'''bold'''''italic''}         {} {<b>bold</b><i>italic</i>}
                                                 # {'''''italic_bold'''''}        {} {<b><i>italic_bold</i></b>}
                                                 # {`fixed`}                      {} {... to be added ...}

                                                 # First get all un-nested hilites
                                                 while {
                                                        [regsub -all {'''([^']+?)'''} $text "\0\1b+\0\\1\0\1b-\0" text] ||
                                                        [regsub -all {''([^']+?)''}   $text "\0\1i+\0\\1\0\1i-\0" text] ||
                                                        [regsub -all {`([^`]+?)`}   $text "\0\1f+\0\\1\0\1f-\0" text]
                                                      } {}

                                                 # And then the remaining ones. This also captures the hilites
                                                 # where the highlighted text contains single apostrophes.
                                                 regsub -all {'''(.+?)'''} $text "\0\1b+\0\\1\0\1b-\0" text
                                                 regsub -all {''(.+?)''}   $text "\0\1i+\0\\1\0\1i-\0" text
                                                 regsub -all {`(.+?)`}   $text "\0\1f+\0\\1\0\1f-\0" text
                                                 regsub -all {(<<br>>)}   $text "\0br\0" text
                                                 regsub -all {(<<nbsp>>)}   $text "\0nbsp\0" text
                                                 regsub -all {(<<pipe>>)}   $text "|" text

                                                 # Normalize brackets ...
                                                 set text [string map {&! [ ]] ]} $text]

    # Listify and generate the final representation of the paragraph.

    ## puts stderr *>>$text<<*

    set len 0
    foreach item [split $text \0] {
      ## puts stderr ====>>$item<<<

      set cmd {} ; set detail {}
      foreach {cmd detail} [split $item \2] break
      set cmd [string trimleft $cmd \1]

      ## puts stderr ====>>$cmd|$detail<<<

      switch -exact -- $cmd {
        b+    {lappend irep b 1}
        b-    {lappend irep b 0}
        i+    {lappend irep i 1}
        i-    {lappend irep i 0}
        f+    {lappend irep f 1}
        f-    {lappend irep f 0}
        br    {lappend irep BR 0}
        nbsp  {lappend irep NBSP 0}
        default {
          if {$detail == {}} {
            # Pure text
            if {$cmd != ""} {
              lappend irep $mode $cmd
              incr len [string length $cmd]
            }
          } else {
            # References.
            #2003-06-20: remove whitespace clutter in page titles
            regsub -all {\s+} [string trim $detail] { } detail
            lappend irep $cmd $detail
            incr len [string length $detail]
          }
        }
      }

      ## puts stderr ======\]>>$irep<<\[
    }

    ## puts stderr ======\]>>$irep<<\[
    return $len
  }

  # =========================================================================
  # =========================================================================

  ### Backend renderer                                   :: Stream ==> Tk ###

  # =========================================================================
  # =========================================================================

  # Output specific conversion. Takes a token stream and converts this into
  # a three-element list. The first element is a list of text fragments and
  # tag-lists, as described at the beginning as the "Tk" format. The second
  # element is a list of triples listing the references found in the page.
  # This second list is required because some information about references
  # is missing from the "Tk" format. And adding them into that format would
  # make the insertion of data into the final text widget ... complex (which
  # is an understatement IMHO). Each triple consists of: url-type (g, u, x),
  # page-local numeric id of url (required for and used in tags) and
  # reference text, in this order.  The third list is a list of embedded
  # images (i.e. stored in "images" view), to be displayed in text widget.

  # Note: The first incarnation of the rewrite to adapt to the new
  # "Stream" format had considerable complexity in the part
  # assembling the output. It kept knowledge about the last used
  # tags and text around, using this to merge runs of text having
  # the same taglist, thus keeping the list turned over to the text
  # widget shorter. Thinking about this I came to the conclusion
  # that removal of this complexity and replacing it with simply
  # unconditional lappend's would gain me time in StreamToTk, but
  # was also unsure how much of a negative effect the generated
  # longer list would have on the remainder of the conversion (setup
  # of link tag behaviour in the text widget, insertion in to the
  # text widget). Especially if the drain would outweigh the gain.
  # As can be seen from the code chosen here, below, I found that
  # the gain through the simplification was much more than the drain
  # later. I gained 0.3 usecs in this stage and lost 0.13 in the
  # next (nearly double time), overall gain 0.17.

  proc FormatTable { resultnm table } {
    variable tableid
    if { ![info exists tableid] } {
      set tableid -1
    }
    upvar 1 $resultnm result
    set row -1
    set col -1
    set tdtag ""
    set trtag ""
    foreach {text tags} $table {
      switch -exact -- $tags {
        CTR - TR - TRH {
          if { $col >= 0 } {
            lappend result \t $tdtag
          }
          incr row
          set col -1
          set tdtag ""
          set trtag ""
          lappend result \n ""
          if { $tags eq "CTR" } {
            if { $row % 2 } {
              set trtag CTR
            } else {
              set trtag TR
            }
          }
        }
        TD - TDH {
          if { $col >= 0 } { 
            set tdtag $tags 
          } else {
            lappend result \t ""
          }
          set tdtag $tags
          incr col
        }
        TDE - TDEH {
          lappend result \t [list $tdtag $trtag]
          set tdtag ""
        }
        default {
          lappend result $text [linsert $tags end $tdtag $trtag]
        }
      }
    }
    # What to do with the table elements?
  }

  proc StreamToTcl {name s {ip ""}} {
    set result ""  ; # Tcl result
    set iscode 0
    set piscode 0
    set blockid 0
    foreach {mode text} $s {
      switch -exact -- $mode {
        Q  { 
          if { !$piscode } { 
            append result "\n\n### <code_block id=$blockid title='[armour $name]'> ############################################################\n"
            incr blockid
          }
          append result \n
          set iscode 2 
        }
        FI { 
          append result "\n\n### <code_block id=$blockid title='$name'> ############################################################\n\n"
          incr blockid
          set iscode 1 
        }
        FE { 
          set iscode 0 
        }
        default {
          if { $iscode } { 
            append result $text
            if { $iscode > 1 } { 
              set iscode 0
              set piscode 1
            }
          } else {
            set piscode 0
          }
        }
      }
    }
    return $result
  }

  # =========================================================================
  # =========================================================================

  ### Backend renderer                                 :: Stream ==> HTML ###

  # =========================================================================

  # InfoProc - get a page for the reference
  # Used for rendering Wiki pages in HTML and as styled text in Tk
  proc InfoProc {ref} {
    set id [WDB LookupPage $ref]
    WDB GetPageVars $id date name

    if {$date == 0} {
      append id @ ;# enter edit mode for missing links
    } else {
      #append id .html
    }

    return [list /$id $name $date]
  }

  # expand a page string to HTML
  proc Expand_HTML {str {db wdb}} {
    StreamToHTML [TextToStream $str] $::env(SCRIPT_NAME) \
      ::WFormat::InfoProc
  }

  # =========================================================================

  # Output specific conversion. Takes a token stream and converts this
  # into HTML. The result is a 2-element list. The first element is the
  # HTML to render. The second element is alist of triplets listing all
  # references found in the stream (each triplet consists reference
  # type, page-local numeric id and reference text).

  proc split_url_link_text { text } {
    if { [string match "*%|%*" $text] } {
      return [split [string map [list "%|%" \1] $text] \1]
    }
    return [list $text $text]
  }

  proc StreamToHTML {s {cgi ""} {ip ""} {creating_preview 0}} {

    # here so we aren't dependent on cksum unless rendering to HTML
    package require cksum

    set result ""
    set tocpos {}
    set state H   ; # bogus hline as initial state.
    set vstate "" ; # Initial state of visual FSM
    set count 0
    set bltype "a"
    set insdelcnt 0
    set centered 0
    set trow 0
    set backrefid 0
    set brefs {}
    set in_header 0
    set tocheader ""
    set uol {}

    variable html_frag

    foreach {mode text} $s {
      if {[llength $uol] && $mode in {HD2 HD3 HD4 HDE BLS BLE TR CTR CT TD TDE TRH TDH TDEH T Q I D H FI FE L F _ CATEGORY}} {
        # Unwind uol
        append result </li>
        foreach uo [lreverse $uol] {
          switch -glob -- $uo {
            *U { append result </ul> }
            *O { append result </ol> }
          }
        }
        set uol {}
      }

      switch -exact -- $mode {
        {}    {
	  if { $in_header } {
            append tocheader [quote $text]
	  }
          append result [quote $text]
        }
        b - i - f {
	  if { $in_header } {
            append tocheader [quote $text]
	  }
          append result $html_frag($mode$text)
        }
        g - G {
          lassign [split_url_link_text $text] link text
	  if { $in_header } {
            append tocheader [quote $text]
	  }
          if {$cgi == ""} {
            append result "\[[quote $text]\]"
            continue
          }
          if {$ip == ""} {
            # no lookup, turn into a searchreference
            append result \
              $html_frag(a_) $cgi$text
            if {$creating_preview} {
              append result "\" target=\"_blank"
            }
            append result $html_frag(tc) \
              [quote $text] $html_frag(_a)
            continue
          }

          set info [eval $ip [list $link]]
          foreach {id name date} $info break

          if {$id == ""} {
            # not found, don't turn into an URL
            append result "\[[quote $text]\]"
            continue
          }

          #regsub {^/} $id {} id
          set id [string trim $id /]
          if {$date > 0} {
            # exists, use ID
            if { $mode eq "G" } {
              append result $html_frag(A_) /_/ref?N=$id
            } else {
              append result $html_frag(a_) /$id
            }
            if {$creating_preview} {
              append result "\" target=\"_blank"
            }
            append result $html_frag(tc) \
              [quote $text] $html_frag(_a)
            continue
          }

          # missing, 
          if { $mode eq "G" } {
            # Insert a plain text
            append result [quote $text]
          } else {
            # use ID -- editor link on the brackets.
            append result \
              $html_frag(a_) /$id 
            if {$creating_preview} {
              append result "\" target=\"_blank"
            }
            append result $html_frag(tc) \[ $html_frag(_a) \
              [quote $text] \
              $html_frag(a_) /$id 
            if {$creating_preview} {
              append result "\" target=\"_blank"
            }
            append result $html_frag(tc) \] $html_frag(_a) \
            }
          }
        u {
          lassign [split_url_link_text $text] link text
	  if { $in_header } {
	    append tocheader [quote $text]
	  }
          append result \
            $html_frag(e_) [quote $link] 
          if {$creating_preview} {
            append result "\" target=\"_blank"
          }
          append result $html_frag(tc) \
            [quote $text] $html_frag(_a)
        }
        x {
          lassign [split_url_link_text $text] link text
	  if { $in_header } {
	    append tocheader [quote $text]
	  }
          if {[regexp -nocase {\.(gif|jpg|jpeg|png)$} $link]} {
            append result $html_frag(i_) $link $html_frag(tc)
          } else {
            if {$text ne $link} {
              append result $html_frag(e_) [quote $link] 
              if {$creating_preview} {
                append result "\" target=\"_blank"
              }
              append result $html_frag(tc) [quote $text] $html_frag(_a)
            } else {
              append result \[ $html_frag(e_) [quote $link] 
              if {$creating_preview} {
                append result "\" target=\"_blank"
              }
              append result $html_frag(tc) [incr count] $html_frag(_a) \]
            }
          }
        }
        V {
          append result $html_frag($state$mode)
          set state $mode
          append result $text
        }
        HD2 - HD3 - HD4 {
          append result "$html_frag($state$mode) id='pagetocXXXXXXXX'>" 
          lappend tocpos [string index $mode 2] [string length $result]
          set state $mode
	  set in_header 1
	  set tocheader ""
        }
        HDE {
          lappend tocpos $tocheader
	  set in_header 0
        }
        BLS {
          append result $html_frag($state$mode)
          foreach {bltype page version who when} [split $text ";"] break
          switch -exact -- $bltype {
            a {
              append result "\n<div class='annotated'>\n"
              append result "  <span class='versioninfo'>\n"
              append result "    <span class='versionnum'><a href='[quote /_/revision?N=$page&V=$version&A=1]'>$version</a></span>\n"
              append result "    <span class='versionwho'>$who</span><br>\n"
              append result "    <span class='versiondate'>$when</span>\n"
              append result "  </span>\n"
            }
            n {
              append result "<div class='newwikiline' id='diff$insdelcnt'>"
              incr insdelcnt
            }
            o {
              append result "<div class='oldwikiline' id='diff$insdelcnt'>"
              incr insdelcnt
            }
            w {
              append result "<div class='whitespacediff' id='diff$insdelcnt'>"
              incr insdelcnt
            }
          }
          set state $mode 
        }
        BLE {
          append result $html_frag($state$mode)
          switch -exact -- $bltype {
            a {
              append result "\n</div>\n"
            }
            w -
            n -
            o {
              append result "</div>"
            }
          }
          set state $mode 
        }
        1O - 2O - 3O - 4O - 5O - 1U - 2U - 3U - 4U - 5U {
          if {[info exists html_frag($state$mode)]} {
            append result $html_frag($state$mode)
          }
          set tag [expr {[string match "?O" $mode]?"<ol>":"<ul>"}]
          set n [string index $mode 0]
          if {[string match "?U" $state] || [string match "?O" $state]} {
            if {$n == [llength $uol]} {
              if {$mode eq [lindex $uol end]} {
                append result "</li><li>"
              } else {
                append result </li>
                set uo [lindex $uol end]
                switch -glob -- $uo {
                  *U { append result </ul> }
                  *O { append result </ol> }
                }
                append result $tag<li>
                lset uol end $mode
              }
            } elseif {$n > [llength $uol]} {
              while {[llength $uol] < $n} {
                append result $tag
                lappend uol $mode
              }
              append result "<li>"
            } else {
              append result "</li>"
              while {[llength $uol] > $n} {
                set uo [lindex $uol end]
                switch -glob -- $uo {
                  *U { append result </ul> }
                  *O { append result </ol> }
                }
                set uol [lrange $uol 0 end-1]
              }
              lset uol end $mode
              append result "<li>"
            }
          } else {
            append result "[string repeat $tag $n]<li>"
            lappend uol {*}[lrepeat $n $mode]
          }
          set state $mode
        }
        TR - CTR - TD - TDE - TRH - TDH - TDEH - T - Q - I - D - H - FI - FE - L - F {
          if { $mode eq "CTR" } { 
            set mode TR
            set oddoreven [expr {$trow % 2 ? "odd" : "even"}]
            incr trow
          } else {
            set oddoreven ""
          }
          append result [subst $html_frag($state$mode)]
          set state $mode
        }
        BR {
          append result "<br>"
        }
        NBSP {
          append result "&nbsp;"
        }
        CT {
          set mode T
          append result $html_frag($state$mode)
          if { $centered } {
            append result "</div><p></p>"
            set centered 0
          } else {
            append result "<div class='centered'><p></p>"
            set centered 1
          }
          set state T
        }
        INLINETOC {
          append result "\n<<TOC>>\n"
        }
        BACKREFS {
          set mode T
          set text [string trim $text]
          append result [subst $html_frag($state$mode)]
          lappend brefs backrefs$backrefid $text
          if { [string length $text]} {
            set htext "<b>$text</b>"
          } else {
            set htext "current page"
          }
          append result "\n<div class='backrefs' id='backrefs$backrefid'>Fetching backrefs for <b>$htext</b>...</div>\n"
          set state T
          incr backrefid
        }
        CATEGORY {
          append result "<hr>"
          append result "<div class='centered'><p></p><table summary='' class='wikit_table'><thead><tr>"
          set text [string map [list "%|%" \1] $text]
          foreach cat [split $text |] {
            append result "<th>"
            set cat  [string map [list \1 "%|%"] $cat]
            lassign [split_url_link_text $cat] link linktext
            set link [string trim $link]
            set linktext [string trim $linktext]
            if {$ip == ""} {
              # no lookup, turn into a searchreference
              append result \
                $html_frag(a_) $cgi$linktext 
              if {$creating_preview} {
                append result "\" target=\"_blank"
              }
              append result $html_frag(tc) \
                [quote $linktext] $html_frag(_a)
              append result "</th>"
              continue
            }
            set info [eval $ip [list $link]]
            foreach {id name date} $info break
            if {$id == ""} {
              # not found, don't turn into an URL
              append result "\[[quote $linktext]\]"
              append result "</th>"
              continue
            }
            #regsub {^/} $id {} id
            set id [string trim $id /]
            if {$date > 0} {
              # exists, use ID
              if { $mode eq "G" } {
                append result $html_frag(A_) /_/ref?N=$id
              } else {
                append result $html_frag(a_) /$id
              }
              if {$creating_preview} {
                append result "\" target=\"_blank"
              }
              append result $html_frag(tc) \
                [quote $linktext] $html_frag(_a)
              append result "</th>"
              continue
            }
            # missing, 
            if { $mode eq "G" } {
              # Insert a plain linktext
              append result [quote $linktext]
            } else {
              # use ID -- editor link on the brackets.
              append result \
                $html_frag(a_) /$id 
              if {$creating_preview} {
                append result "\" target=\"_blank"
              }
              append result $html_frag(tc) \[ $html_frag(_a) \
                [quote $linktext] \
                $html_frag(a_) /$id 
              if {$creating_preview} {
                append result "\" target=\"_blank"
              }
              append result $html_frag(tc) \] $html_frag(_a) \
            }
            append result "</th>"
          }
          append result "</tr></thead></table></div><p></p>"
        }
      }
    }
    # Close off the last section.
    if { [info exists html_frag(${state}_)] } {
      append result $html_frag(${state}_)
    }

    # Create page-TOC
    set toc ""
    if { [llength $tocpos] } {
      append toc "<div class='toc1'>Page contents\n"
      set i 0
      foreach {ht tpb thdr} $tocpos {
        set l [expr {$ht-2}]
        # Init lvl
        set img($i,0) " "
        set img($i,1) " "
        set img($i,2) " "
        # Join-branch for current level
        set img($i,$l) "+"
        incr i
      }      

      # Join-end for last entry on each level
      set cl -1
      set act(0) 0
      set act(1) 0
      set act(2) 0
      for { set j [expr {$i-1}] } { $j >= 0 } { incr j -1 } { 
        for { set k 0 } { $k < 3 } { incr k } { 
          if { $img($j,$k) eq "+" } {
	    if { !$act($k) } {
              set img($j,$k) "-"
	    }
	    set act($k) 1
	    for { set l [expr {$k+1}] } { $l < 3 } { incr l } { 
              set act($l) 0
	    }
          }
        }
      }
      # Line to lower on same level
      set act(0) 0
      set act(1) 0
      for { set j [expr {$i-1}] } { $j >= 0 } { incr j -1 } { 
        for { set k 0 } { $k < 3 } { incr k } { 
          if { $img($j,$k) eq "+" || $img($j,$k) eq "-" } { 
	    set act($k) 1
          }
        }
        if { $img($j,0) eq "+" || $img($j,0) eq "-" } {
          set act(1) 0
        }
        if { $act(0) && $img($j,0) eq " " } { 
          set img($j,0) "|"
        }
        if { $act(1) && ($img($j,0) eq " " || $img($j,0) eq "|")  && $img($j,1) eq " " } { 
          set img($j,1) "|"
        }
      }

      set hdl2 {}
      set hdl3 {}
      set hdl4 {}
      set i 0
      foreach {ht tpb thdr} $tocpos {
        if { $ht == 2 } {
          set hdl2 $thdr
          set hdl3 {}
          set hdl4 {}
        } elseif { $ht == 3 } { 
          set hdl3 $thdr
          set hdl4 {}
        } elseif { $ht == 4 } { 
          set hdl4 $thdr
        }
        set tkn [::crc::CksumInit]
        ::crc::CksumUpdate $tkn $hdl2$hdl3$hdl4
        set cksum [::crc::CksumFinal $tkn]
        append toc "<div class='ptoc'>"
        for { set j 0 } { $j < 3 } { incr j } { 
          if { $img($i,$j) eq "+" } {
            append toc "<img class='ptoc' src='join.gif'>"
            break
          } elseif { $img($i,$j) eq "-" } {
            append toc "<img class='ptoc' src='joinbottom.gif'>"
            break
          } elseif { $img($i,$j) eq "|" } {
            append toc "<img class='ptoc' src='line.gif'>"
          } elseif { $img($i,$j) eq " " } {
            append toc "<img class='ptoc' src='empty.gif'>"            
          }
        }
        set ltxt [string map {\  &nbsp;} [armour_quote $thdr]]
        append toc "&nbsp;<a class='toc' href='#pagetoc[format %08x $cksum]'>[tclarmour $ltxt]</a>"
        append toc "</div>\n"
        set result [string replace $result [expr {$tpb-10}] [expr {$tpb-3}] [format %08x $cksum]]
      incr i
      }
      append toc "</div>"
    }

    # Get rid of spurious newline at start of each quoted area.
    regsub -all "<pre>\n" $result "<pre>" result

    list $result {} $toc $brefs
  }

  proc quote {q} {
    regsub -all {&} $q {\&amp;}  q
    regsub -all \" $q {\&quot;} q
    regsub -all {<} $q {\&lt;}   q
    regsub -all {>} $q {\&gt;}   q
    regsub -all "&amp;(#\\d+;)" $q {\&\1}   q
    return $q
  }

  # Define inter-section tagging, logical vertical space used between each
  # logical section of text.
  #		| Current              (. <=> 1)
  #  Last	| T  Q  U  O  I  D  H
  # ----------+----------------------
  #  Text   T | See below
  #  Quote  Q |
  #  Bullet U |
  #  Enum   O |
  #  Term   I |
  #  T/def  D |
  #  HRULE  H |
  # ----------+----------------------

  variable  html_frag
  proc vs {last current text} {
    variable html_frag
    set      html_frag($last$current) $text
    return
  }

  vs T    T                      <p></p> ;vs T    Q                      <pre> ;vs T    U                      <ul\ class='ul3'><li> ;vs T    O                      <ol><li>
  vs Q    T                </pre><p></p> ;vs Q    Q                         \n ;vs Q    U                </pre><ul\ class='ul3'><li> ;vs Q    O                </pre><ol><li>
  vs U    T                 </ul><p></p> ;vs U    Q                 </ul><pre> ;vs U    U                        \n<li> ;vs U    O                 </ul><ol><li>
  vs O    T                 </ol><p></p> ;vs O    Q                 </ol><pre> ;vs O    U                 </ol><ul\ class='ul3'><li> ;vs O    O                        \n<li>
  vs I    T                 </dl><p></p> ;vs I    Q                 </dl><pre> ;vs I    U                 </dl><ul\ class='ul3'><li> ;vs I    O                 </dl><ol><li>
  vs D    T            </dd></dl><p></p> ;vs D    Q            </dd></dl><pre> ;vs D    U            </dd></dl><ul\ class='ul3'><li> ;vs D    O            </dd></dl><ol><li>
  vs H    T                      <p></p> ;vs H    Q                      <pre> ;vs H    U                      <ul\ class='ul3'><li> ;vs H    O                      <ol><li>
  vs TDE  T </tr></tbody></table><p></p> ;vs TDE  Q </tr></tbody></table><pre> ;vs TDE  U </tr></tbody></table><ul\ class='ul3'><li> ;vs TDE  O </tr></tbody></table><ol><li>
  vs TDEH T </tr></thead></table><p></p> ;vs TDEH Q </tr></thead></table><pre> ;vs TDEH U </tr></thead></table><ul\ class='ul3'><li> ;vs TDEH O </tr></thead></table><ol><li>
  vs FE   T                </pre><p></p> ;vs FE   Q                         \n ;vs FE   U                </pre><ul\ class='ul3'><li> ;vs FE   O                </pre><ol><li>
  vs FI   T                      <p></p> ;vs FI   Q                      <pre> ;vs FI   U                      <ul\ class='ul3'><li> ;vs FI   O                      <ol><li>
  vs L    T              </table><p></p> ;vs L    Q              </table><pre> ;vs L    U              </table><ul\ class='ul3'><li> ;vs L    O              </table><ol><li>
  vs HD2  T                 </h2><p></p> ;vs HD2  Q                 </h2><pre> ;vs HD2  U                 </h2><ul\ class='ul3'><li> ;vs HD2  O                 </h2><ol><li>
  vs HD3  T                 </h3><p></p> ;vs HD3  Q                 </h3><pre> ;vs HD3  U                 </h3><ul\ class='ul3'><li> ;vs HD3  O                 </h3><ol><li>
  vs HD4  T                 </h4><p></p> ;vs HD4  Q                 </h4><pre> ;vs HD4  U                 </h4><ul\ class='ul3'><li> ;vs HD4  O                 </h4><ol><li>
  vs BLS  T                    <p></p>\n ;vs BLS  Q                    \n<pre> ;vs BLS  U                    \n<ul\ class='ul3'><li> ;vs BLS  O                    \n<ol><li>
  vs BLE  T                    <p></p>\n ;vs BLE  Q                    \n<pre> ;vs BLE  U                    \n<ul\ class='ul3'><li> ;vs BLE  O                    \n<ol><li>

  vs T    I                      <dl><dt> ;vs T    D                      <dl><dd> ;vs T    H                              "<hr>" ;vs T    _                    {}
  vs Q    I                </pre><dl><dt> ;vs Q    D                </pre><dl><dd> ;vs Q    H                        "</pre><hr>" ;vs Q    _                </pre>
  vs U    I                 </ul><dl><dt> ;vs U    D                 </ul><dl><dd> ;vs U    H                         "</ul><hr>" ;vs U    _                 </ul>
  vs O    I                 </ol><dl><dt> ;vs O    D                 </ol><dl><dd> ;vs O    H                         "</ol><hr>" ;vs O    _                 </ol>
  vs I    I                          <dt> ;vs I    D                     </dt><dd> ;vs I    H                         "</dl><hr>" ;vs I    _                 </dl>
  vs D    I                     </dd><dt> ;vs D    D                     </dd><dd> ;vs D    H                    "</dd></dl><hr>" ;vs D    _            </dd></dl>
  vs H    I                      <dl><dt> ;vs H    D                      <dl><dd> ;vs H    H                              "<hr>" ;vs H    _                    {}
  vs TDE  I </tr></tbody></table><dl><dt> ;vs TDE  D </tr></tbody></table><dl><dd> ;vs TDE  H     "</tr></tbody></table><p></p><hr>" ;vs TDE  _ </tr></tbody></table>
  vs TDEH I </tr></thead></table><dl><dt> ;vs TDEH D </tr></thead></table><dl><dd> ;vs TDEH H     "</tr></thead></table><p></p><hr>" ;vs TDEH _ </tr></thead></table>
  vs FE   I                </pre><dl><dt> ;vs FE   D                </pre><dl><dd> ;vs FE   H                        "</pre><hr>" ;vs FE   _                </pre>
  vs FI   I                      <dl><dt> ;vs FI   D                      <dl><dd> ;vs FI   H                              "<hr>" ;vs FI   _                    {}
  vs L    I              </table><dl><dt> ;vs L    D              </table><dl><dd> ;vs L    H                      "</table><hr>" ;vs L    _              </table>
  vs HD2  I                 </h2><dl><dt> ;vs HD2  D                 </h2><dl><dd> ;vs HD2  H                         "</h2><hr>" ;vs HD2  _                 </h2>
  vs HD3  I                 </h3><dl><dt> ;vs HD3  D                 </h3><dl><dd> ;vs HD3  H                         "</h3><hr>" ;vs HD3  _                 </h3>
  vs HD4  I                 </h4><dl><dt> ;vs HD4  D                 </h4><dl><dd> ;vs HD4  H                         "</h4><hr>" ;vs HD4  _                 </h4>
  vs BLS  I                    \n<dl><dt> ;vs BLS  D                    \n<dl><dd> ;vs BLS  H                              \n<hr> ;vs BLS  _                    \n
  vs BLE  I                    \n<dl><dt> ;vs BLE  D                    \n<dl><dd> ;vs BLE  H                              \n<hr> ;vs BLE  _                    \n

  vs T    HD2                      <h2 ;vs T    HD3                      <h3 ;vs T    HD4                      <h4
  vs Q    HD2                </pre><h2 ;vs Q    HD3                </pre><h3 ;vs Q    HD4                </pre><h4
  vs U    HD2                 </ul><h2 ;vs U    HD3                 </ul><h3 ;vs U    HD4                 </ul><h4
  vs O    HD2                 </ol><h2 ;vs O    HD3                 </ol><h3 ;vs O    HD4                 </ol><h4
  vs I    HD2                 </dl><h2 ;vs I    HD3                 </dl><h3 ;vs I    HD4                 </dl><h4
  vs D    HD2            </dd></dl><h2 ;vs D    HD3            </dd></dl><h3 ;vs D    HD4            </dd></dl><h4
  vs H    HD2                      <h2 ;vs H    HD3                      <h3 ;vs H    HD4                      <h4
  vs TDE  HD2 </tr></tbody></table><h2 ;vs TDE  HD3 </tr></tbody></table><h3 ;vs TDE  HD4 </tr></tbody></table><h4
  vs TDEH HD2 </tr></thead></table><h2 ;vs TDEH HD3 </tr></thead></table><h3 ;vs TDEH HD4 </tr></thead></table><h4
  vs FE   HD2                </pre><h2 ;vs FE   HD3                </pre><h3 ;vs FE   HD4                </pre><h4
  vs FI   HD2                      <h2 ;vs FI   HD3                      <h3 ;vs FI   HD4                      <h4
  vs L    HD2              </table><h2 ;vs L    HD3              </table><h3 ;vs L    HD4              </table><h4
  vs HD2  HD2                 </h2><h2 ;vs HD2  HD3                 </h2><h3 ;vs HD2  HD4                 </h2><h4
  vs HD3  HD2                 </h3><h2 ;vs HD3  HD3                 </h3><h3 ;vs HD3  HD4                 </h3><h4
  vs HD4  HD2                 </h4><h2 ;vs HD4  HD3                 </h4><h3 ;vs HD4  HD4                 </h4><h4
  vs BLS  HD2                    \n<h2 ;vs BLS  HD3                    \n<h3 ;vs BLS  HD4                    \n<h4
  vs BLE  HD2                    \n<h2 ;vs BLE  HD3                    \n<h3 ;vs BLE  HD4                    \n<h4

  vs T    BLS                      \n ;vs T    BLE                      \n
  vs Q    BLS                </pre>\n ;vs Q    BLE                </pre>\n
  vs U    BLS                 </ul>\n ;vs U    BLE                 </ul>\n
  vs O    BLS                 </ol>\n ;vs O    BLE                 </ol>\n
  vs I    BLS                 </dl>\n ;vs I    BLE                 </dl>\n
  vs D    BLS            </dd></dl>\n ;vs D    BLE            </dd></dl>\n
  vs H    BLS                      \n ;vs H    BLE                      \n
  vs TDE  BLS </tr></tbody></table>\n ;vs TDE  BLE </tr></tbody></table>\n
  vs TDEH BLS </tr></thead></table>\n ;vs TDEH BLE </tr></thead></table>\n
  vs FE   BLS                </pre>\n ;vs FE   BLE                </pre>\n
  vs FI   BLS                </pre>\n ;vs FI   BLE                </pre>\n
  vs L    BLS         </tr></table>\n ;vs L    BLE              </table>\n
  vs HD2  BLS                 </h2>\n ;vs HD2  BLE                 </h2>\n
  vs HD3  BLS                 </h3>\n ;vs HD3  BLE                 </h3>\n
  vs HD4  BLS                 </h4>\n ;vs HD4  BLE                 </h4>\n
  vs BLS  BLS                      \n ;vs BLS  BLE                      \n
  vs BLE  BLS                      \n ;vs BLE  BLE                      \n

  vs T    L       "<table summary='' class=wikit_options><tr>"
  vs Q    L "</pre><table summary='' class=wikit_options><tr>"
  vs U    L  "</ul><table summary='' class=wikit_options><tr>"
  vs O    L  "</ol><table summary='' class=wikit_options><tr>"
  vs I    L  "</dl><table summary='' class=wikit_options><tr>"
  vs D    L  "</dd></dl><table summary='' class=wikit_options><tr>"
  vs H    L       "<table summary='' class=wikit_options><tr>"
  vs TDE  L                                        "</tr><tr>"
  vs TDEH L                                        "</tr><tr>"
  vs FE   L "</pre><table summary='' class=wikit_options><tr>"
  vs FI   L       "<table summary='' class=wikit_options><tr>"
  vs L    L                                             "<tr>"
  vs HD2  L  "</h2><table summary='' class=wikit_options><tr>"
  vs HD3  L  "</h3><table summary='' class=wikit_options><tr>"
  vs HD4  L  "</h4><table summary='' class=wikit_options><tr>"
  vs BLS  L     "\n<table summary='' class=wikit_options><tr>"
  vs BLE  L     "\n<table summary='' class=wikit_options><tr>"

  vs T    TR       "<table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs Q    TR "</pre><table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs U    TR  "</ul><table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs O    TR  "</ol><table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs I    TR  "</dl><table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs D    TR  "</dd></dl><table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs H    TR       "<table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs TDE  TR                                             "</tr><tr class='\$oddoreven'>"
  vs TDEH TR                              "</tr></thead><tbody><tr class='\$oddoreven'>"
  vs FE   TR "</pre><table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs FI   TR       "<table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs L    TR                                           "<tbody><tr class='\$oddoreven'>"
  vs HD2  TR  "</h2><table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs HD3  TR  "</h3><table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs HD4  TR  "</h4><table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs BLS  TR     "\n<table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs BLE  TR     "\n<table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  
  vs T    TRH       "<table summary='' class=wikit_table><thead><tr>"
  vs Q    TRH "</pre><table summary='' class=wikit_table><thead><tr>"
  vs U    TRH  "</ul><table summary='' class=wikit_table><thead><tr>"
  vs O    TRH  "</ol><table summary='' class=wikit_table><thead><tr>"
  vs I    TRH  "</dl><table summary='' class=wikit_table><thead><tr>"
  vs D    TRH  "</dd></dl><table summary='' class=wikit_table><thead><tr>"
  vs H    TRH       "<table summary='' class=wikit_table><thead><tr>"
  vs TDE  TRH                              "</tr></tbody><thead><tr>"
  vs TDEH TRH                              "</tr></tbody><thead><tr>"
  vs FE   TRH "</pre><table summary='' class=wikit_table><thead><tr>"
  vs FI   TRH       "<table summary='' class=wikit_table><thead><tr>"
  vs L    TRH                                           "<thead><tr>"
  vs HD2  TRH  "</h2><table summary='' class=wikit_table><thead><tr>"
  vs HD3  TRH  "</h3><table summary='' class=wikit_table><thead><tr>"
  vs HD4  TRH  "</h4><table summary='' class=wikit_table><thead><tr>"
  vs BLS  TRH     "\n<table summary='' class=wikit_table><thead><tr>"
  vs BLE  TRH     "\n<table summary='' class=wikit_table><thead><tr>"

  vs T    FI                      <pre> ;vs T   FE                    {} ;
  vs Q    FI                </pre><pre> ;vs Q   FE                </pre> ;
  vs U    FI                 </ul><pre> ;vs U   FE                 </ul> ;
  vs O    FI                 </ol><pre> ;vs O   FE                 </ol> ;
  vs I    FI                 </dl><pre> ;vs I   FE                 </dl> ;
  vs D    FI            </dd></dl><pre> ;vs D   FE            </dd></dl> ;
  vs H    FI                      <pre> ;vs H   FE                    {} ;
  vs TDE  FI </tr></tbody></table><pre> ;vs TDE FE </tr></tbody></table> ;
  vs TDEH FI </tr></thead></table><pre> ;vs TDE FE </tr></thead></table> ;
  vs FE   FI                </pre><pre> ;vs FE  FE                </pre> ;
  vs FI   FI                      <pre> ;vs FI  FE                    {} ;
  vs L    FI              </table><pre> ;vs L   FE              </table> ;
  vs HD2  FI                 </h2><pre> ;vs HD2 FE                 </h2> ;
  vs HD3  FI                 </h3><pre> ;vs HD3 FE                 </h3> ;
  vs HD4  FI                 </h4><pre> ;vs HD4 FE                 </h4> ;
  vs BLS  FI                    \n<pre> ;vs BLS FE                    \n ;
  vs BLE  FI                    \n<pre> ;vs BLE FE                    \n ;

  # Only TR and TDE can go to TD
  # TDE -> TDE is never required.
  vs TR  TD  <td>
  vs TDE TD  <td>
  vs TD  TDE </td>

  vs TRH  TDH  <th>
  vs TDEH TDH  <th>
  vs TDH  TDEH </th>

  vs L F "<td class=wikit_options><pre class=wikit_options>"
  vs V F "</td></tr><tr><td class=wikit_options><pre class=wikit_options>"
  vs F V "</pre></td><td class=wikit_options>"
  vs V V {}
  vs F L "</pre></td><td class=wikit_options></td></tr>"
  vs V L </td></tr>

  proc l { pl t s e } { 
    variable html_frag
    set T T
    for { set l $s } { $l <= $e } { incr l } { 
      foreach p $pl {
        if {[info exists html_frag($T$p)]} {
          vs $l$t $p $html_frag($T$p)
        }
        if {[info exists html_frag($p$T)]} {
          vs $p $l$t $html_frag($p$T)
        }
      }
    }
  }
  set pl {T Q I D H TDE TDEH TRH TR FE FI L HD2 HD3 HD4 BLS BLE _}

  l $pl O 1 5
  l $pl U 1 5

  array set html_frag {
    a_ {<a href="}         b0 </b> f0 </tt>
    A_ {<a class='backreflink' href="}
	_a {</a>}              b1 <b>  f1 <tt>
        i_ {<img alt="" src="} i0 </i>
    tc {">}                i1 <i>
        e_ {<a rel="nofollow" href="}
  } ; # "

  # =========================================================================
  # =========================================================================

  ### Backend renderer                                 :: Stream ==> Refs ###

  # =========================================================================
  # =========================================================================

  # Output specific conversion. Extracts all wiki internal page references
  # from the token stream and returns them as a list of page id's.

  proc StreamToRefs {s ip} {
    array set pages {}

    foreach {mode text} $s {
      if {[string equal $mode g]} {

        set info [eval $ip [list $text]]
        foreach {id name date} $info break
        if {$id == ""} {continue}
        
        regexp {[0-9]+} $id id
        set pages($id) ""
      } elseif {[string equal $mode "CATEGORY"]} {
        set text [string map [list "%|%" \1] $text]
        foreach cat [split $text |] {
          set cat  [string map [list \1 "%|%"] $cat]
          lassign [split_url_link_text $cat] link linktext
          set link [string trim $link]
          set linktext [string trim $linktext]

          set info [eval $ip [list $link]]
          foreach {id name date} $info break
          if {$id == ""} {continue}
          
          regexp {[0-9]+} $id id
          set pages($id) ""          
        }
      }
    }

    array names pages
  }

  # Output specific conversion. Extracts all external references
  # from the token stream and returns them as a list of urls.

  proc StreamToUrls {s} {
    array set urls {}
    foreach {mode text} $s {
      if {$mode eq "u"} { set urls($text) imm }
      if {$mode eq "x"} { set urls($text) ref }
    }
    array get urls
  }

  proc FormatWikiToc { C } {
    variable protected
    if { [string length $C] == 0 } {
      return ""
    }
    set result ""
    set toce ""
    set imtoc {}
    foreach line [split $C \n] {
      if {[string length [string trim $line]]==0} continue
      if {[string index $line 0] eq "+"} continue
      if {[string is alnum [string index $line 0]]} {
        if {[string length $result]} {
          if {[string length $toce]} {
            append result "<div class='toc3'>$toce</div>\n"
            set toce ""
          }
          append result "</div>\n"
        }
        append result "<div class='toc1'>$line\n"
      } elseif {[regexp {^\s*(.+?)\s+(\[.*\])\s*(.*)} $line - opt link imurl]} {
        if {[string length $toce]} {
          append result "<div class='toc2'>$toce</div>\n"
        }
        set link [string trim $link {[]}]
        if { [string length $opt] } {
          set p [WDB LookupPage $link]
          set toce "<a class='toc' href='/$p'>[armour_quote $opt]</a>"
          lappend imtoc [string trim $imurl] $p
        } else {
          set toce ""
        }
      }
    }
    if {[string length $toce]} {
      append result "<div class='toc3'>$toce</div>\n"
    }
    if {[string length $result]} {
      append result "</div>\n"
    }
    return [list $result $imtoc]
  }

  proc armour_quote { t } {
    return [string map {\" &quot; ' &#39\;} $t]
  }
    
  proc markInsDel { l insdelcntnm } {
    upvar $insdelcntnm insdelcnt
    set result ""
    while {
           [regsub -all {~~~~([^`]+?)~~~~} $l "\0\1o+\0\\1\0\1o-\0" l] ||
           [regsub -all {\^\^\^\^([^`]+?)\^\^\^\^} $l "\0\1n+\0\\1\0\1n-\0" l]
         } {}
    
    set len 0
    foreach item [split $l \0] {
      
      set cmd [string trimleft $item \1]
      
      switch -exact -- $cmd {
        n+      {append result "<ins id='diff$insdelcnt'>" ; incr insdelcnt}
        n-      {append result </ins>}
        o+      {append result "<del id='diff$insdelcnt'>" ; incr insdelcnt}
        o-      {append result </del>}

        default {
          if {$cmd != ""} {
            append result [quote $cmd]
          }
        }
      }
    }
    return $result
  }

  proc ShowDiffs { t } {
    set insdelcnt 0
    set ctxt ""
    set result "<pre class='prediff'>"
    foreach l [split $t "\n"] {
      if { [string match ">>>>>>*" $l] } { 
        append result [markInsDel $ctxt insdelcnt]
        set ctxt ""
        foreach {bltype page version who when} [split [string range $l 6 end] ";"] break
        if { $bltype eq "n" } {
          append result "<div class='newwikiline' id='diff$insdelcnt'>"
        } else {
          append result "<div class='oldwikiline' id='diff$insdelcnt'>"
        }
        incr insdelcnt
      } elseif { $l eq "<<<<<<" } {
        append result [markInsDel $ctxt insdelcnt]
        set ctxt ""
        append result "</div>"
      } else {
        append ctxt $l\n
      }
    }
    append result [markInsDel $ctxt insdelcnt]
    append result </pre>
    return $result
  }

    namespace export -clear *
    namespace ensemble create -subcommands {}
} ;# end of namespace

### Local Variables: ***
### mode:tcl ***
### tcl-indent-level:2 ***
### tcl-continued-indent-level:2 ***
### indent-tabs-mode:nil ***
### End: ***


