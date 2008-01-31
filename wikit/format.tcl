# format.tcl -- Formatter for wiki markup text, CGI as well as GUI
# originally written by Jean-Claude Wippler, 2000..2007 - may be used freely

package provide Wikit::Format 1.1

namespace eval Wikit::Format {
  namespace export TextToStream StreamToTk StreamToTcl StreamToHTML StreamToRefs \
    StreamToUrls Expand_HTML FormatTocJavascriptDtree ShowDiffs

  # In this file:
  #
  # proc TextToStream {text} -> stream
  # proc StreamToTk {stream infoProc} -> {{tagged-text} {urls}}
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

  proc TextToStream {text {fixed 0} {code 0}} {
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
        HR - UL - OL - DL {set empty_std 0}
        default {}
      }

      ## Whenever we encounter a special line, including quoted, we
      ## have to render the data of the preceding paragraph, if
      ## there is any.
      #
      switch -exact -- $tag {
        HR - UL - OL - DL - PRE - TBL - CTBL - TBLH - HD2 - HD3 - HD4 - BLAME_START - BLAME_END - CENTERED - BACKREFS {
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
        UL  {lappend irep U 0 ; render $txt}
        OL  {lappend irep O 0 ; render $txt}
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
          if {$txt != {}} {rlinks $txt}
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
            lappend paragraph $txt
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
          set id [Wikit::LookupPage $name]
          set page [Wikit::GetPage $id]
          # delete any code markup in the page (this allows the
          # page to be displayed as code markup but still be run)
          regsub -all {(^======\n|\n======\n|\n======$)} $page {} page
          if {[catch {set txt [eval_interp eval $page]} msg]} {
            puts "msg = $msg"
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
          foreach te [lrange [split [string range $txt 1 end-1] "|"] 1 end-1] {
            lappend irep TDH 0 ; render $te ; lappend irep TDEH 0
          }
        }
        CTBL {
          lappend irep CTR 0
          foreach te [lrange [split [string range $txt 1 end-1] "|"] 1 end-1] {
            lappend irep TD 0 ; render $te ; lappend irep TDE 0
          }
        }
        TBL {
          lappend irep TR 0
          foreach te [lrange [split $txt "|"] 1 end-1] {
            lappend irep TD 0 ; render $te ; lappend irep TDE 0
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
        BACKREFS {
          lappend irep BACKREFS $txt
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
      UL	{^(   + {0,2})(\*) (\S.*)$}
      OL	{^(   + {0,2})(\d)\. (\S.*)$}
      DL	{^(   + {0,2})([^:]+):   (\S.*)$}

      UL	{^(   +)(\*) (\S.*)$}
      OL	{^(   +)(\d)\. (\S.*)$}
      DL	{^(   +)([^:]+):   (\S.*)$}

      FIXED  {^()()(===)$}
      CODE   {^()()(======)$}
      OPTION {^()()(\+\+\+)$}
      #EVAL {^(\+eval)(\s?)(.+)$}
      BLAME_START {^(>>>>>>)(\s?)(.+)$}
      BLAME_END   {^(<<<<<<)$}
      CENTERED {^()()(!!!!!!)$}
      BACKREFS {^(<<backrefs>>)()(.*)$}
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
    set bpre  {\[(brefs:)([^\]]*)]}  ; #  page back-references ; # compat
    #set lre  {\m(https?|ftp|news|mailto|file):(\S+[^\]\)\s\.,!\?;:'>"])} ; # "
    #set lre  {\m(https?|ftp|news|mailto|file):([^\s:]+[^\]\)\s\.,!\?;:'>"])} ; # "
    set lre  {\m(https?|ftp|news|mailto|file):([^\s:]\S*[^\]\)\s\.,!\?;:'>"])} ; # "
    set lre2 {\m(https?|ftp|news|mailto|file):([^\s:]\S*[^\]\)\s\.,!\?;:'>"]%\|%[^%]+%\|%)} ; # "

    set blre "\\\[\0\1u\2(\[^\0\]*)\0\\\]"

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
                                                 regsub -all $lre2 $text "\0\1u\2\\1\3\\2\0" text
                                                 regsub -all $lre  $text "\0\1u\2\\1\3\\2\0" text
                                                 set text [string map {\3 :} $text]
                                                 ## puts stderr C>>$text<<*

                                                 # External links in brackets are simpler cause we know where the
                                                 # links are already.
                                                 regsub -all $blre $text "\0\1x\2\\1\0" text
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

  proc StreamToTk {s N {ip ""} {brp ""}} {
    variable tagmap ; # pre-assembled information, tags and spacing
    variable vspace ; # ....
    #              ; # State of renderer
    set urls   ""  ; # List of links found
    set eims   ""  ; # List of embedded images
    set result ""  ; # Tk result
    set state  T   ; # Assume a virtual paragraph in front of the actual data
    set count  0   ; # Id counter for page references
    set xcount 0   ; # Id counter for bracketed external references
    set number 0   ; # Counter for items in enumerated lists
    set b      0   ; # State of bold emphasis    - 0 = off, 1 = on
    set i      0   ; # State of italic emphasis  - 0 = off, 1 = on
    set f      0   ; # State of fixed-width font - 0= off, 1 = on
    set incl   0   ; # included file? (0 = no, 1 = yes)
    set tresult {} ; # Temporary result for tables
    set cresult result

    foreach {mode text} $s {
      switch -exact -- $mode {
        Q - T - I - D - C - U - O - H - L - F - V - X - FI - FE - HD2 - HD3 - HD4 - BR - NBSP {
          if {[llength $tresult]} {
            FormatTable result $tresult
            set tresult {}
          }
          set cresult result
        }
        TR - CTR - TRH - TD - TDE - TDH - TDEH {
          set cresult tresult
        }
      }
      switch -exact -- $mode {
        {} {
          if {$text == {}} {continue}
          if {$incl && $state eq "C"} {
            # prepend three spaces to each line of included file
            set new [join [split $text \n] "\n   "]
            if {$new ne $text} {
              set text "   $new"
            }
          }
          lappend $cresult $text $tagmap($state$b$i$f)
        }
        b - i - f {set $mode $text }
        g - G {
          lassign [split_url_link_text $text] link text
          set     n    [incr count]
          lappend urls $mode $n $link
          set     tags [set base $tagmap($state$b$i$f)]

          lappend tags url $mode$n

          if {$ip == ""} {
            lappend $cresult $text $tags
            continue
          }

          set info [lindex [eval $ip [list $text]] 2]

          if {$info == "" || $info == 0} {
            lappend $cresult \[ $tags $text $base \] $tags
            continue
          }

          lappend $cresult $text $tags
        }
        u {
          lassign [split_url_link_text $text] link text
          set n [incr count]
          lappend urls u $n $link

          set tags $tagmap($state$b$i$f)
          if {[lindex $tags 0] == "fixed"} {
            lappend tags urlq u$n
          } else {
            lappend tags url u$n
          }
          lappend $cresult $text $tags
        }
        x {
          lassign [split_url_link_text $text] link text
          # support embedded images if present in "images" view
          set iseq ""
          if {[regexp -nocase {\.(gif|jpg|jpeg|png)$} $link - ifmt]} {
            set ifmt [string tolower $ifmt]
            set iseq [mk::select wdb.images url $link -count 1]
            if {$iseq != "" && [info commands eim_$iseq] == ""} {
              if {$ifmt eq "jpg"} { set ifmt jpeg }
              catch { package require tkimg::$ifmt }
              catch {
                image create photo eim_$iseq -format $ifmt \
                  -data [mk::get wdb.images!$iseq image]
              }
            }
          }
          if {[info commands eim_$iseq] != ""} {
            #puts "-> $xcount $text"
            lappend $cresult " " eim_$iseq
            lappend eims eim_$iseq
          } else {
            set n [incr xcount]
            lappend urls x $n $link

            set     tags [set base $tagmap($state$b$i$f)]
            lappend tags url x$n
            lappend $cresult \[ $base $n $tags \] $base
          }
        }
        Q {
          set number 0 ;# reset counter for items in enumerated lists
          # use the body tag for the space before a quoted string
          # so the don't get a gray background.
          lappend $cresult $vspace($state$mode) $tagmap(T000)
          set state $mode
        }
        T - I - D - C {
          set number 0 ;# reset counter for items in enumerated lists
          lappend $cresult $vspace($state$mode) $tagmap(${mode}000)
          set state $mode
        }
        U {
          lappend $cresult \
            "$vspace($state$mode)   \u2022  " $tagmap(${mode}000)
          set state $mode
        }
        O {
          lappend $cresult \
            "$vspace($state$mode)   [incr number].\t" \
            $tagmap(${mode}000)
          set state $mode
        }
        H {
          lappend $cresult \
            $vspace($state$mode) $tagmap(T000) \
            \t                   $tagmap(Hxxx) \
            \n                   $tagmap(H000)
          set state $mode
        }
        L {	# start/end of option list
          set text [split $text]
          set optnum [lindex $text 0]
          if {[set len [lindex $text 1]] ne ""} {
            # end - set width of fixed part of option block
            catch {Wikit::optwid $optnum $len} 
            set state T
          }
        }
        F { # fixed text part of option declaration
          set indent "   "
          lappend $cresult $vspace(TF)$indent $tagmap(F000)$optnum
          set state F
        }
        V { # variable text part of option declaration
          set tag $tagmap(V$b$i$f)
          set font [lindex $tag 0]$optnum
          set attr [lrange $tag 1 end]
          lappend $cresult $text "$font $attr"
        }
        X {
          set incl $text
        }
        f {
          if {$text} {
            set oldstate $state
            set state Y
          } else {
            set state $oldstate
          }
        }
        CTR - TR - TRH {
          lappend $cresult $vspace($state$mode) $tagmap(T000) $mode $mode
          set state $mode
        }
        TD - TDH {
          lappend $cresult $mode $mode
          set state TD
        }
        TDE - TDEH {
          lappend $cresult TDE TDE
          set state TDE
        }
        HD2 - HD3 - HD4 {
          lappend $cresult $vspace($state$mode) ""
          set state $mode
        }
        BLS {
          lappend $cresult $text body
        }
        BLE {
          lappend $cresult $text body
        }
        BR {
          lappend $cresult "\n" body
          set state T
        }
        NBSP {
          lappend $cresult " " body
          set state T
        }
        CT {
          lappend $cresult "\n" body
        }
        BACKREFS {
          if { $brp eq "" } {
            if { [string length $text]} {
              lappend $cresult "Back references to current page not available." body
            } else {
              lappend $cresult "Back references to '$text' not available." body
            }
          } else {
            lappend $cresult "\n" body
            if { [string length $text]} {
              set refList [eval $brp [list $text]]
            } else {
              set refList [eval $brp $N]
            }
            
            foreach br $refList {
              lassign $br date name who from
              set     n    [incr count]
              lappend urls g $n $name
              lappend $cresult "\n   \u2022 " body $name [list url g$n]
            }
            lappend $cresult "\n" body
#            lappend $cresult $text body
          }
        }
      }
    }
    if {[llength $tresult]} {
      FormatTable result $tresult
    }
    list [lappend result "" body] $urls $eims
  }

  # Map from the tagcodes used in StreamToTk above to the taglist
  # used in the text widget the generated text will be inserted into.

  variable  tagmap
  array set tagmap {

    T000 body     T010 {body i}    T100 {body b}  T110 {body bi}
    T001 {body f} T011 {body fi}   T101 {body fb} T111 {body fbi}

    Q000 fixed    Q010 {fi}   Q100 {fb}   Q110 {fbi}
    Q001 fixed    Q011 {fi}   Q101 {fb}   Q111 {fbi}

    H000 thin     H010 {thin i}  H100 {thin b}  H110 {thin bi}
    H000 {thin f} H010 {thin fi} H100 {thin fb} H110 {thin fbi}

    U000 ul     U010 {ul i}  U100 {ul b}  U110 {ul bi}
    U001 {ul f} U011 {ul fi} U101 {ul fb} U111 {ul fbi}

    O000 ol     O010 {ol i}  O100 {ol b}  O110 {ol bi}
    O001 {ol f} O010 {ol fi} O100 {ol fb} O110 {ol fbi}

    I000 dt     I010 {dt i}  I100 {dt b}  I110 {dt bi}
    I001 {dt f} I011 {dt fi} I101 {dt fb} I111 {dt fbi}

    D000 dl     D010 {dl i}  D100 {dl b}  D110 {dl bi}
    D001 {dl f} D011 {dl fi} D101 {dl fb} D111 {dl fbi}

    C000 code     C010 {code fi} C100 {code fb} C110 {code fbi}
    C001 {code f} C011 {code fi} C101 {code fb} C111 {code fbi}

    V000 {optvar}   V010 {optvar vi}       V100 {optvar vb}       V110 {optvar vbi}
    V001 {optvar f} V011 {optvar f vi} V101 {optvar f vb} V111 {optvar f vbi}

    F000 {optfix}   F010 {optfix fi} F100 {optfix fb} F110 {optfix fbi}
    F001 {optfix f} F011 {optfix fi} F101 {optfix fb} F111 {optfix fbi}

    Y000 fwrap     Y010 {fwrap i}  Y100 {fwrap b}  Y110 {fwrap bi}
    Y001 {fwrap f} Y011 {fwrap fi} Y101 {fwrap fb} Y111 {fwrap fbi}

    Hxxx {hr thin}

    TR000  body     TR010  {body i}  TR100  {body b}  TR110  {body bi}
    TR001  {body f} TR011  {body fi} TR101  {body fb} TR111  {body fbi}

    CTR000  body     CTR010  {body i}  CTR100  {body b}  CTR110  {body bi}
    CTR001  {body f} CTR011  {body fi} CTR101  {body fb} CTR111  {body fbi}

    TRH000  body     TRH010  {body i}  TRH100  {body b}  TRH110  {body bi}
    TRH001  {body f} TRH011  {body fi} TRH101  {body fb} TRH111  {body fbi}

    TD000  body     TD010  {body i}  TD100  {body b}  TD110  {body bi}
    TD001  {body f} TD011  {body fi} TD101  {body fb} TD111  {body fbi}

    TDH000  body     TDH010  {body i}  TDH100  {body b}  TDH110  {body bi}
    TDH001  {body f} TDH011  {body fi} TDH101  {body fb} TDH111  {body fbi}

    TDE000 body     TDE010 {body i}  TDE100 {body b}  TDE110 {body bi}
    TDE001 {body f} TDE011 {body fi} TDE101 {body fb} TDE111 {body fbi}

    TDEH000 body     TDEH010 {body i}  TDEH100 {body b}  TDEH110 {body bi}
    TDEH001 {body f} TDEH011 {body fi} TDEH101 {body fb} TDEH111 {body fbi}

    HD2000 title     HD2010 {title  i} HD2100 {title b}  HD2110 {title bi}
    HD2001 {title f} HD2011 {title fi} HD2101 {title fb} HD2111 {title fbi}

    HD3000 title3     HD3010 {title3 i}  HD3100 {title4 b}  HD3110 {title3 bi}
    HD3001 {title3 f} HD3011 {title3 fi} HD3101 {title4 fb} HD3111 {title3 fbi}

    HD4000 title4     HD4010 {title4 i}  HD4100 {title3 b}  HD4110 {title4 bi}
    HD4001 {title4 f} HD4011 {title4 fi} HD4101 {title3 fb} HD4111 {title4 fbi}
  }

  # Define amount of vertical space used between each logical section of text.
  #			| Current              (. <=> 1)
  #  Last		| T  Q  U  O  I  D  H  C  X  Y
  # ----------+-----------------------------
  #  Text   T | 2  2  2  2  2  1  2  1  0  0
  #  Quote  Q | 2  1  2  2  2  1  3  1  0  0
  #  Bullet U | 2  2  1  1  1  1  2  1  0  0
  #  Enum   O | 2  2  1  1  1  1  2  1  0  0
  #  Term   I | 2  2  1  1  1  1  2  1  0  0
  #  T/def  D | 2  2  1  1  1  1  2  1  0  0
  #  HRULE  H | 1  1  1  1  1  1  2  1  1  1
  #  CODE   C | 2  2  2  2  2  1  3  1  0  0
  #  INCL   X | 0  0  0  0  0  0  2  0  0  0
  #  fixed  Y | 0  0  0  0  0  0  2  0  0  0
  # ----------+-----------------------------

  variable  vspace
  proc vs {last current dummy n} {
    variable vspace
    set      vspace($last$current) [string repeat \n $n]
    return
  }

  vs T T --- 2 ; vs T Q --- 2 ; vs T U --- 2 ; vs T O --- 2 ; vs T I --- 2
  vs Q T --- 2 ; vs Q Q --- 1 ; vs Q U --- 2 ; vs Q O --- 2 ; vs Q I --- 2
  vs U T --- 2 ; vs U Q --- 2 ; vs U U --- 1 ; vs U O --- 1 ; vs U I --- 1
  vs O T --- 2 ; vs O Q --- 2 ; vs O U --- 1 ; vs O O --- 1 ; vs O I --- 1
  vs I T --- 2 ; vs I Q --- 2 ; vs I U --- 1 ; vs I O --- 1 ; vs I I --- 1
  vs D T --- 2 ; vs D Q --- 2 ; vs D U --- 1 ; vs D O --- 1 ; vs D I --- 1
  vs H T --- 1 ; vs H Q --- 1 ; vs H U --- 1 ; vs H O --- 1 ; vs H I --- 1

  vs T D --- 1 ; vs T H --- 2
  vs Q D --- 1 ; vs Q H --- 3
  vs U D --- 1 ; vs U H --- 2
  vs O D --- 1 ; vs O H --- 2
  vs I D --- 1 ; vs I H --- 2
  vs D D --- 1 ; vs D H --- 2
  vs H D --- 1 ; vs H H --- 2

  # support for fixed font / code blocks
  vs T C --- 1 ; vs Q C --- 1 ; vs U C --- 1 ; vs O C --- 1 ; vs I C --- 1
  vs D C --- 1 ; vs H C --- 1

  vs C T   --- 2 ; vs C Q   --- 2 ; vs C U   --- 2 ; vs C O --- 2 ; vs C I --- 2
  vs C D   --- 1 ; vs C H   --- 3 ; vs C C   --- 1 ; vs C X --- 0 ; vs C Y --- 0
  vs C HD2 --- 2 ; vs C HD3 --- 2 ; vs C HD4 --- 2

  # support for options
  vs L F --- 0 ; vs F V -- 0 ; vs V T --- 1 ; vs T F --- 1 ; vs L T --- 1
  vs F T --- 1

  # support for included files/evals
  vs X T   --- 0 ; vs X Q   --- 0 ; vs X U   --- 0 ; vs X O --- 0 ; vs X I --- 0
  vs X D   --- 0 ; vs X H   --- 1 ; vs X C   --- 0 ; vs X X --- 0 ; vs X Y --- 0
  vs X HD2 --- 0 ; vs X HD3 --- 0 ; vs X HD4 --- 0

  # fixed font
  vs Y T   --- 0 ; vs Y Q   --- 0 ; vs Y U   --- 0 ; vs Y O --- 0 ; vs Y I --- 0
  vs Y D   --- 0 ; vs Y H   --- 1 ; vs Y C   --- 0 ; vs Y X --- 0 ; vs Y I --- 0
  vs Y HD2 --- 0 ; vs Y HD3 --- 0 ; vs Y HD4 --- 0

  # support for tables
  vs TDE T   --- 2  ;vs TDE Q --- 2  ;vs TDE U   --- 2  ;vs TDE O   --- 2
  vs TDE I   --- 2  ;vs TDE D --- 2  ;vs TDE H   --- 3  ;vs TDE C   --- 2
  vs TDE X   --- 2  ;vs TDE Y --- 3  ;vs TDE HD2 --- 2 ; vs TDE HD3 --- 2
  vs TDE HD4 --- 2

  vs TDEH T   --- 2  ;vs TDEH Q --- 2  ;vs TDEH U   --- 2  ;vs TDEH O   --- 2
  vs TDEH I   --- 2  ;vs TDEH D --- 2  ;vs TDEH H   --- 3  ;vs TDEH C   --- 2
  vs TDEH X   --- 2  ;vs TDEH Y --- 3  ;vs TDEH HD2 --- 2 ; vs TDEH HD3 --- 2
  vs TDEH HD4 --- 2

  vs T   TR --- 1  ;vs Q   TR --- 2  ;vs U    TR --- 1  ;vs O   TR --- 1
  vs I   TR --- 1  ;vs D   TR --- 1  ;vs H    TR --- 1  ;vs TDE TR --- 0
  vs C   TR --- 1  ;vs X   TR --- 1  ;vs Y    TR --- 1  ;vs HD2 TR --- 1
  vs HD3 TR --- 1  ;vs HD4 TR --- 1  ;vs TDEH TR --- 0

  vs T   TRH --- 1  ;vs Q   TRH --- 2  ;vs U    TRH --- 1  ;vs O   TRH --- 1
  vs I   TRH --- 1  ;vs D   TRH --- 1  ;vs H    TRH --- 1  ;vs TDE TRH --- 0
  vs C   TRH --- 1  ;vs X   TRH --- 1  ;vs Y    TRH --- 2  ;vs HD2 TRH --- 1
  vs HD3 TRH --- 1  ;vs HD4 TRH --- 1  ;vs TDEH TRH --- 0

  vs T   CTR --- 1  ;vs Q   CTR --- 2  ;vs U    CTR --- 1  ;vs O   CTR --- 1
  vs I   CTR --- 1  ;vs D   CTR --- 1  ;vs H    CTR --- 1  ;vs TDE CTR --- 0
  vs C   CTR --- 1  ;vs X   CTR --- 1  ;vs Y    CTR --- 2  ;vs HD2 CTR --- 1
  vs HD3 CTR --- 1  ;vs HD4 CTR --- 1  ;vs TDEH CTR --- 0

  # headers
  vs HD2 T   --- 2 ; vs HD2 Q   --- 2 ; vs HD2 U --- 2 ; vs HD2 O --- 2 ; vs HD2 I --- 2
  vs HD2 D   --- 2 ; vs HD2 H   --- 3 ; vs HD2 C --- 2 ; vs HD2 X --- 0 ; vs HD2 Y --- 0
  vs HD2 HD2 --- 2 ; vs HD2 HD3 --- 2 ; vs HD2 HD4 --- 2

  vs HD3 T   --- 2 ; vs HD3 Q   --- 2 ; vs HD3 U   --- 2 ; vs HD3 O --- 2 ; vs HD3 I --- 2
  vs HD3 D   --- 2 ; vs HD3 H   --- 3 ; vs HD3 C   --- 2 ; vs HD3 X --- 0 ; vs HD3 Y --- 0
  vs HD3 HD2 --- 2 ; vs HD3 HD3 --- 2 ; vs HD3 HD4 --- 2

  vs HD4 T   --- 2 ; vs HD4 Q   --- 2 ; vs HD4 U   --- 2 ; vs HD4 O --- 2 ; vs HD4 I --- 2
  vs HD4 D   --- 2 ; vs HD4 H   --- 3 ; vs HD4 C   --- 2 ; vs HD4 X --- 0 ; vs HD4 Y --- 0
  vs HD4 HD2 --- 2 ; vs HD4 HD3 --- 2 ; vs HD4 HD4 --- 2

  vs T HD2 --- 2 ; vs Q HD2 --- 2 ; vs U HD2 --- 2 ; vs O HD2 --- 2 ; vs I HD2 --- 2
  vs D HD2 --- 2 ; vs H HD2 --- 3 ; vs C HD2 --- 2 ; vs X HD2 --- 0 ; vs Y HD2 --- 0

  vs T HD3 --- 2 ; vs Q HD3 --- 2 ; vs U HD3 --- 2 ; vs O HD3 --- 2 ; vs I HD3 --- 2
  vs D HD3 --- 2 ; vs H HD3 --- 3 ; vs C HD3 --- 2 ; vs X HD3 --- 0 ; vs Y HD3 --- 0

  vs T HD4 --- 2 ; vs Q HD4 --- 2 ; vs U HD4 --- 2 ; vs O HD4 --- 2 ; vs I HD4 --- 2
  vs D HD4 --- 2 ; vs H HD4 --- 3 ; vs C HD4 --- 2 ; vs X HD4 --- 0 ; vs Y HD4 --- 0

  catch {rename vs {}}

  proc StreamToTcl {s {ip ""}} {
    set result ""  ; # Tcl result
    set iscode 0
    set piscode 0
    set blockid 0
    foreach {mode text} $s {
      switch -exact -- $mode {
        Q  { 
          if { !$piscode } { 
            append result "\n### <code_block id=$blockid> ############################################################\n\n"
            incr blockid
          }
          set iscode 2 
        }
        FI { 
          append result "\n### <code_block id=$blockid> ############################################################\n\n"
          incr blockid
          set iscode 1 
        }
        FE { set iscode 0 }
        default {
          if { $iscode } { 
            append result "$text\n" 
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

  # expand a page string to HTML
  proc Expand_HTML {str {db wdb}} {
    StreamToHTML [TextToStream $str] $::env(SCRIPT_NAME) \
      [list ::Wikit::InfoProc $db]
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

  proc StreamToHTML {s {cgi ""} {ip ""}} {

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

    variable html_frag

    foreach {mode text} $s {
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
              $html_frag(a_) $cgi$text $html_frag(tc) \
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
              append result $html_frag(A_) _ref/$id
            } else {
              append result $html_frag(a_) $id
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
              $html_frag(a_) $id $html_frag(tc) \[ $html_frag(_a) \
              [quote $text] \
              $html_frag(a_) $id $html_frag(tc) \] $html_frag(_a) \
            }
          }
        u {
          lassign [split_url_link_text $text] link text
	  if { $in_header } {
	    append tocheader [quote $text]
	  }
          append result \
            $html_frag(e_) [quote $link] $html_frag(tc) \
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
            append result \
              \[ $html_frag(e_) [quote $link] $html_frag(tc) \
              [incr count] $html_frag(_a) \]
          }
        }
        V {
          append result $html_frag($state$mode)
          set state $mode
          append result $text
        }
        HD2 - HD3 - HD4 {
          if {$mode eq "HD2"} {
            append result "$html_frag($state$mode) id='pagetocXXXXXXXX'>" 
          } else {
            append result "$html_frag($state$mode)>" 
          }
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
              append result "    <span class='versionnum'><a href='[quote /_revision/$page?V=$version&A=1]'>$version</a></span>\n"
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
        TR - CTR - TD - TDE - TRH - TDH - TDEH - T - Q - I - D - U - O - H - FI - FE - L - F {
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
            append result "</p></div><p>"
            set centered 0
          } else {
            append result "</p><div class='centered'><p>"
            set centered 1
          }
          set state T
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
      }
    }
    # Close off the last section.
    if { [info exists html_frag(${state}_)] } {
      append result $html_frag(${state}_)
    }

    # Create page-TOC as dtree javascript
    set toc ""
    if { [llength $tocpos] } {
      append toc "<a class='pagetoc'>Page contents</a><ul>\n"
      foreach {ht tpb thdr} $tocpos {
        if { $ht == 2 } {
          set tkn [::crc::CksumInit]
          ::crc::CksumUpdate $tkn $thdr
          set cksum [::crc::CksumFinal $tkn]
          append toc "<li class='pagetoc'><a class='pagetoc' href='#pagetoc[format %08x $cksum]'>[armour_quote $thdr]</a></li>\n"
          set result [string replace $result [expr {$tpb-10}] [expr {$tpb-3}] [format %08x $cksum]]
        }
      }
      append toc "</ul>\n"
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

  vs T    T                  </p><p> ;vs T    Q                  </p><pre> ;vs T    U                  </p><ul><li> ;vs T    O                  </p><ol><li>
  vs Q    T                </pre><p> ;vs Q    Q                         \n ;vs Q    U                </pre><ul><li> ;vs Q    O                </pre><ol><li>
  vs U    T                 </ul><p> ;vs U    Q                 </ul><pre> ;vs U    U                        \n<li> ;vs U    O                 </ul><ol><li>
  vs O    T                 </ol><p> ;vs O    Q                 </ol><pre> ;vs O    U                 </ol><ul><li> ;vs O    O                        \n<li>
  vs I    T                 </dl><p> ;vs I    Q                 </dl><pre> ;vs I    U                 </dl><ul><li> ;vs I    O                 </dl><ol><li>
  vs D    T                 </dl><p> ;vs D    Q                 </dl><pre> ;vs D    U                 </dl><ul><li> ;vs D    O                 </dl><ol><li>
  vs H    T                      <p> ;vs H    Q                      <pre> ;vs H    U                      <ul><li> ;vs H    O                      <ol><li>
  vs TDE  T </tr></tbody></table><p> ;vs TDE  Q </tr></tbody></table><pre> ;vs TDE  U </tr></tbody></table><ul><li> ;vs TDE  O </tr></tbody></table><ol><li>
  vs TDEH T </tr></thead></table><p> ;vs TDEH Q </tr></thead></table><pre> ;vs TDEH U </tr></thead></table><ul><li> ;vs TDEH O </tr></thead></table><ol><li>
  vs FE   T                </pre><p> ;vs FE   Q                         \n ;vs FE   U                </pre><ul><li> ;vs FE   O                </pre><ol><li>
  vs FI   T                      <p> ;vs FI   Q                      <pre> ;vs FI   U                      <ul><li> ;vs FI   O                      <ol><li>
  vs L    T              </table><p> ;vs L    Q              </table><pre> ;vs L    U              </table><ul><li> ;vs L    O              </table><ol><li>
  vs HD2  T                 </h2><p> ;vs HD2  Q                 </h2><pre> ;vs HD2  U                 </h2><ul><li> ;vs HD2  O                 </h2><ol><li>
  vs HD3  T                 </h3><p> ;vs HD3  Q                 </h3><pre> ;vs HD3  U                 </h3><ul><li> ;vs HD3  O                 </h3><ol><li>
  vs HD4  T                 </h4><p> ;vs HD4  Q                 </h4><pre> ;vs HD4  U                 </h4><ul><li> ;vs HD4  O                 </h4><ol><li>
  vs BLS  T                    <p>\n ;vs BLS  Q                    \n<pre> ;vs BLS  U                    \n<ul><li> ;vs BLS  O                    \n<ol><li>
  vs BLE  T                    <p>\n ;vs BLE  Q                    \n<pre> ;vs BLE  U                    \n<ul><li> ;vs BLE  O                    \n<ol><li>

  vs T    I                  </p><dl><dt> ;vs T    D                  </p><dl><dd> ;vs T    H                  "</p><hr>" ;vs T    _                  </p>
  vs Q    I                </pre><dl><dt> ;vs Q    D                </pre><dl><dd> ;vs Q    H                "</pre><hr>" ;vs Q    _                </pre>
  vs U    I                 </ul><dl><dt> ;vs U    D                 </ul><dl><dd> ;vs U    H                 "</ul><hr>" ;vs U    _                 </ul>
  vs O    I                 </ol><dl><dt> ;vs O    D                 </ol><dl><dd> ;vs O    H                 "</ol><hr>" ;vs O    _                 </ol>
  vs I    I                          <dt> ;vs I    D                          <dd> ;vs I    H                 "</dl><hr>" ;vs I    _                 </dl>
  vs D    I                          <dt> ;vs D    D                          <dd> ;vs D    H                 "</dl><hr>" ;vs D    _                 </dl>
  vs H    I                      <dl><dt> ;vs H    D                      <dl><dd> ;vs H    H                      "<hr>" ;vs H    _                    {}
  vs TDE  I </tr></tbody></table><dl><dt> ;vs TDE  D </tr></tbody></table><dl><dd> ;vs TDE  H "</tr></tbody></table><hr>" ;vs TDE  _ </tr></tbody></table>
  vs TDEH I </tr></thead></table><dl><dt> ;vs TDEH D </tr></thead></table><dl><dd> ;vs TDEH H "</tr></thead></table><hr>" ;vs TDEH _ </tr></thead></table>
  vs FE   I                </pre><dl><dt> ;vs FE   D                </pre><dl><dd> ;vs FE   H                "</pre><hr>" ;vs FE   _                </pre>
  vs FI   I                      <dl><dt> ;vs FI   D                      <dl><dd> ;vs FI   H                      "<hr>" ;vs FI   _                    {}
  vs L    I              </table><dl><dt> ;vs L    D              </table><dl><dd> ;vs L    H              "</table><hr>" ;vs L    _              </table>
  vs HD2  I                 </h2><dl><dt> ;vs HD2  D                 </h2><dl><dd> ;vs HD2  H                 "</h2><hr>" ;vs HD2  _                 </h2>
  vs HD3  I                 </h3><dl><dt> ;vs HD3  D                 </h3><dl><dd> ;vs HD3  H                 "</h3><hr>" ;vs HD3  _                 </h3>
  vs HD4  I                 </h4><dl><dt> ;vs HD4  D                 </h4><dl><dd> ;vs HD4  H                 "</h4><hr>" ;vs HD4  _                 </h4>
  vs BLS  I                    \n<dl><dt> ;vs BLS  D                    \n<dl><dd> ;vs BLS  H                      \n<hr> ;vs BLS  _                    \n
  vs BLE  I                    \n<dl><dt> ;vs BLE  D                    \n<dl><dd> ;vs BLE  H                      \n<hr> ;vs BLE  _                    \n

  vs T    HD2                  </p><h2 ;vs T    HD3                  </p><h3 ;vs T    HD4                  </p><h4
  vs Q    HD2                </pre><h2 ;vs Q    HD3                </pre><h3 ;vs Q    HD4                </pre><h4
  vs U    HD2                 </ul><h2 ;vs U    HD3                 </ul><h3 ;vs U    HD4                 </ul><h4
  vs O    HD2                 </ol><h2 ;vs O    HD3                 </ol><h3 ;vs O    HD4                 </ol><h4
  vs I    HD2                 </dl><h2 ;vs I    HD3                 </dl><h3 ;vs I    HD4                 </dl><h4
  vs D    HD2                 </dl><h2 ;vs D    HD3                 </dl><h3 ;vs D    HD4                 </dl><h4
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

  vs T    BLS                  </p>\n ;vs T    BLE                  </p>\n
  vs Q    BLS                </pre>\n ;vs Q    BLE                </pre>\n
  vs U    BLS                 </ul>\n ;vs U    BLE                 </ul>\n
  vs O    BLS                 </ol>\n ;vs O    BLE                 </ol>\n
  vs I    BLS                 </dl>\n ;vs I    BLE                 </dl>\n
  vs D    BLS                 </dl>\n ;vs D    BLE                 </dl>\n
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

  vs T    L   "</p><table summary='' class=wikit_options><tr>"
  vs Q    L "</pre><table summary='' class=wikit_options><tr>"
  vs U    L  "</ul><table summary='' class=wikit_options><tr>"
  vs O    L  "</ol><table summary='' class=wikit_options><tr>"
  vs I    L  "</dl><table summary='' class=wikit_options><tr>"
  vs D    L  "</dl><table summary='' class=wikit_options><tr>"
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

  vs T    TR   "</p><table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs Q    TR "</pre><table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs U    TR  "</ul><table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs O    TR  "</ol><table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs I    TR  "</dl><table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
  vs D    TR  "</dl><table summary='' class=wikit_table><tbody><tr class='\$oddoreven'>"
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
  
  vs T    TRH   "</p><table summary='' class=wikit_table><thead><tr>"
  vs Q    TRH "</pre><table summary='' class=wikit_table><thead><tr>"
  vs U    TRH  "</ul><table summary='' class=wikit_table><thead><tr>"
  vs O    TRH  "</ol><table summary='' class=wikit_table><thead><tr>"
  vs I    TRH  "</dl><table summary='' class=wikit_table><thead><tr>"
  vs D    TRH  "</dl><table summary='' class=wikit_table><thead><tr>"
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

  vs T    FI                  </p><pre> ;vs T   FE                  </p> ;
  vs Q    FI                </pre><pre> ;vs Q   FE                </pre> ;
  vs U    FI                 </ul><pre> ;vs U   FE                 </ul> ;
  vs O    FI                 </ol><pre> ;vs O   FE                 </ol> ;
  vs I    FI                 </dl><pre> ;vs I   FE                 </dl> ;
  vs D    FI                 </dl><pre> ;vs D   FE                 </dl> ;
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

  vs L F <td><pre>
  vs V F </td></tr><tr><td><pre>
  vs F V </pre></td><td>
  vs V V {}
  vs F L </pre></td><td></td></tr>
  vs V L </td></tr>
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
      if {![string equal $mode g]} {continue}

      set info [eval $ip [list $text]]
      foreach {id name date} $info break
      if {$id == ""} {continue}

      regexp {[0-9]+} $id id
      set pages($id) ""
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

  proc FormatTocJavascriptDtree { C } {
    variable protected
    if { [string length $C] == 0 } {
      return ""
    }
    set parent 0
    set first ""
    set cnt 0
    set result ""
    append result "d = new dTree('d');\n"
    append result "d.clearCookie();\n"	;# temporary code to delete old cookies
    append result "d.config.useCookies = false;\n"
    append result "d.config.useLines = 1;\n"
    append result "d.config.useIcons = 0;\n"
    append result "d.add($cnt,-1,'Wiki contents');\n"
    set toccnt $cnt
    incr cnt
    append result "d.add($cnt,-1,'<br>Categories');\n"
    set catparent $cnt
    incr cnt
    foreach line [split $C \n] {
      if {[string index $line 0] eq "+"} continue
      if {[string is alnum [string index $line 0]]} {
        if { [string index [string trim $line] end] eq "*" } {
          # Show backreferences in toc
          set refs [mk::select wdb.refs to [::Wikit::LookupPage $line wdb]]
          set refList ""
          foreach r $refs {
            set r [mk::get wdb.refs!$r from]
            ::Wikit::pagevars $r name
            lappend refList [list $name $r]
          }
          append result "d.add($cnt,$toccnt,'[armour_quote [string range [string trim $line] 0 end-1]]');\n"
          set parent $cnt
          incr cnt
          foreach x [lsort -dict -index 0 [lsort -dict $refList]] {
            lassign $x name r
            # Strip Category and * if present
            if {[string range $name 0 8] eq "Category "} {
              set name [string range $name 9 end]
            }
            if { [string index [string trim $name] end] eq "*" } {
              set name [string range [string trim $name] 0 end-1]
            }
            if { [string length $name] } {
              append result "d.add($cnt,$parent,'[armour_quote $name]', '/$r')\n"
              incr cnt
            }
          }
        } else {
          if { [string length $line] } {
            if { [string match "Category *" $line] } {
              if { $catparent < 0 } {
                append result "d.add($cnt,$toccnt,'Categories');\n"
                set catparent $cnt
                incr cnt
              }
#              append result "d.add($cnt,$catparent,'[armour_quote $line]');\n"
              # Strip "Category "
              set cname [string range $line 9 end]
              append result "d.add($cnt,$catparent,'[armour_quote $cname]');\n"
              set parent $cnt
              incr cnt
            } else {
              append result "d.add($cnt,$toccnt,'[armour_quote $line]');\n"
              set parent $cnt
              incr cnt
            }
          }
        }
      } elseif {[regexp {^\s*(.+?)(\*{0,1})\s+(\[.*\])(\*?)} $line - opt ref link rest brefs]} {
        set link [string trim $link {[]}]
        if { [string length $opt] } {
          if { [string length $brefs] } {
            append result "d.add($cnt,$parent,'[armour_quote $opt]','/_ref/[::Wikit::LookupPage $link wdb]?P=1');\n"
          } else {
            append result "d.add($cnt,$parent,'[armour_quote $opt]','/[::Wikit::LookupPage $link wdb]');\n"
          }
          incr cnt
        }
      }
    }
    append result "document.getElementById(containerid).innerHTML=d;\n"
    return $result
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

} ;# end of namespace

### Local Variables: ***
### mode:tcl ***
### tcl-indent-level:2 ***
### tcl-continued-indent-level:2 ***
### indent-tabs-mode:nil ***
### End: ***
