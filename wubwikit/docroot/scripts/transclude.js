/***********************************************
 * Dynamic Ajax Content- © Dynamic Drive DHTML code library (www.dynamicdrive.com)
 * This notice MUST stay intact for legal use
 * Visit Dynamic Drive at http://www.dynamicdrive.com/ for full source code
 * Based on functions taken from Dynamic Ajax Content:
 *    ajaxpage
 *    loadpage
 ***********************************************/
    
function ajaxtocpage(url, containerid){
    var page_request = false
    if (window.XMLHttpRequest) // if Mozilla, Safari etc
        page_request = new XMLHttpRequest()
    else if (window.ActiveXObject){ // if IE
	try {
	    page_request = new ActiveXObject("Msxml2.XMLHTTP")
	} 	
	catch (e){
	    try{
		page_request = new ActiveXObject("Microsoft.XMLHTTP")
	    }
	    catch (e){}
	}
    }
    else
        return false
    page_request.onreadystatechange=function(){
	loadtocpage(page_request, containerid)
    }
    page_request.open('GET', url, true)
    page_request.send(null)
}

function loadtocpage(page_request, containerid){
    if (page_request.readyState == 4 && (page_request.status==200 || window.location.href.indexOf("http")==-1)) {
	if (page_request.responseText.length) {
	    eval(page_request.responseText);
	}
    }
}
    
function ajaxbackrefspage(url, containerid){
    var page_request = false
    if (window.XMLHttpRequest) // if Mozilla, Safari etc
        page_request = new XMLHttpRequest()
    else if (window.ActiveXObject){ // if IE
	try {
	    page_request = new ActiveXObject("Msxml2.XMLHTTP")
	} 	
	catch (e){
	    try{
		page_request = new ActiveXObject("Microsoft.XMLHTTP")
	    }
	    catch (e){}
	}
    }
    else
        return false
    page_request.onreadystatechange=function(){
	loadbackrefspage(page_request, containerid)
    }
    page_request.open('GET', url, true)
    page_request.send(null)
}

function loadbackrefspage(page_request, containerid){
    if (page_request.readyState == 4 && (page_request.status==200 || window.location.href.indexOf("http")==-1)) {
	if (page_request.responseText.length) {
	    document.getElementById(containerid).innerHTML = page_request.responseText;
	}
    }
}

function ajaxinittocpages(){
    ajaxtocpage('/_toc', 'wiki_toc');
    document.getElementById('wrapper').style.marginLeft = '-160px';
    document.getElementById('content').style.marginLeft = '160px';
    document.getElementById('menu_area').style.display = 'inline';
    document.getElementById('gsearchform').style.display = 'inline';
}

function ajaxtocpages(){
    document.getElementById('wiki_menu').style.display='inline';
    document.getElementById('page_toc').style.display='inline';
    document.getElementById('wiki_toc').style.display='inline';
    document.getElementById('wrapper').style.marginLeft = '-160px';
    document.getElementById('content').style.marginLeft = '160px';
    document.getElementById('menu_area').style.display='inline';
}

function ajaxnotocpages(){
    document.getElementById('wiki_menu').style.display='none';
    document.getElementById('page_toc').style.display='none';
    document.getElementById('wiki_toc').style.display='none';
    document.getElementById('wrapper').style.marginLeft = '0';
    document.getElementById('wrapper').style.marginRight = '-5px';
    document.getElementById('content').style.marginLeft = '5px';
    document.getElementById('menu_area').style.display='none';
}

function setCookie( name, value, expires, path, domain, secure ) 
{
  // set time, it's in milliseconds
  var today = new Date();
  today.setTime( today.getTime() );
  
  /*
    if the expires variable is set, make the correct 
    expires time, the current script below will set 
    it for x number of days, to make it for hours, 
    delete * 24, for minutes, delete * 60 * 24
  */
  if ( expires ) {
    expires = expires * 1000 * 60 * 60 * 24;
  }
  var expires_date = new Date( today.getTime() + (expires) );
  
  document.cookie = name + "=" +escape( value ) +
    ( ( expires ) ? ";expires=" + expires_date.toGMTString() : "" ) + 
    ( ( path ) ? ";path=" + path : "" ) + 
    ( ( domain ) ? ";domain=" + domain : "" ) +
    ( ( secure ) ? ";secure" : "" );
}

// [Cookie] Clears a cookie
function clearCookie(name, path) {
  var now = new Date();
  var yesterday = new Date(now.getTime() - 1000 * 60 * 60 * 24);
  setCookie(name, 'cookieValue', yesterday, path);
};

// this fixes an issue with the old method, ambiguous values 
// with this test document.cookie.indexOf( name + "=" );
function getCookie( check_name ) {
  // first we'll split this cookie up into name/value pairs
  // note: document.cookie only returns name=value, not the other components
  var a_all_cookies = document.cookie.split( ';' );
  var a_temp_cookie = '';
  var cookie_name = '';
  var cookie_value = '';
  var b_cookie_found = false; // set boolean t/f default f
  
  for ( i = 0; i < a_all_cookies.length; i++ )
    {
      // now we'll split apart each name=value pair
      a_temp_cookie = a_all_cookies[i].split( '=' );
      
      
      // and trim left/right whitespace while we're at it
      cookie_name = a_temp_cookie[0].replace(/^\s+|\s+$/g, '');
      
      // if the extracted name matches passed check_name
      if ( cookie_name == check_name )
	{
	  b_cookie_found = true;
	  // we need to handle case where cookie has no value but exists (no = sign, that is):
	  if ( a_temp_cookie.length > 1 )
	    {
	      cookie_value = unescape( a_temp_cookie[1].replace(/^\s+|\s+$/g, '') );
	    }
	  // note that in cases where cookie is initialized but no value, null is returned
	  return cookie_value;
	  break;
	}
      a_temp_cookie = null;
      cookie_name = '';
    }
  if ( !b_cookie_found )
    {
      return null;
    }
}				

function checkTOC()
{
    ajaxinittocpages();

    needs_toc=getCookie('wiki_toc');
    if (needs_toc==null || needs_toc=="" || needs_toc=="1") {
	ajaxtocpages();
    }
    else {
	ajaxnotocpages();
    }
}

function getBackRefs(page,containerid)
{
    ajaxbackrefspage("/_ref/" + page + "?A=1", containerid)
}


function toggleTOC()
{
    needs_toc=getCookie('wiki_toc')
    if (needs_toc==null || needs_toc=="" || needs_toc=="1") {
	ajaxnotocpages();
	setCookie('wiki_toc', 0, 30, "/_toc/");
    } else {
	ajaxtocpages();
	setCookie('wiki_toc', 1, 30, "/_toc/");
    }
}

function clearGoogle() {
	var txt = document.getElementById('googletxt');
	txt.style.color = 'black';
	txt.value = '';
}

function setGoogle() {
	var txt = document.getElementById('googletxt');
	txt.style.color = 'gray';
	if (txt.value == '') {
		txt.value = 'Search';
	}
}

function URLencode(sStr) {
    return escape(sStr)
	.replace(/\+/g, '%2B')
	.replace(/\"/g,'%22')
	.replace(/\'/g, '%27');
}

function App(query) {
    this.query = query;
    this.resultCount = 0;
    this.siteSearch = new GwebSearch();
    this.siteSearch.setUserDefinedLabel("Tcler's wiki");
    this.siteSearch.setUserDefinedClassSuffix("siteSearch");
    this.siteSearch.setSiteRestriction("http://wiki.tcl.tk");
    this.siteSearch.setResultSetSize(GSearch.LARGE_RESULTSET);
    this.siteSearch.setSearchCompleteCallback(this, App.prototype.OnSearchComplete);
    document.getElementById("page_toc").innerHTML = "";
    document.title = "Search";
    document.getElementById("title").innerHTML = "Search";
    document.getElementById("updated").innerHTML = "";
    document.getElementById("wiki_menu").innerHTML = "<ul id='menu'><li><a href='http://wiki.tcl.tk'>Home</a></li><li><a href='/4'>Recent changes</a></li><li><a href='/3'>Help</a></li></ul>";
    document.getElementById("footer").innerHTML = "<a href='http://wiki.tcl.tk'>Home</a> &bull; <a href='/4'>Recent changes</a> &bull; <a href='/3'>Help</a> &bull; <a href='/2'>Search</a>";
    document.getElementById("content").innerHTML = "<p><div id='searchprogress'>Searching for &quot;<b>" + query + "</b>&quot;...</div></p>";
    this.siteSearch.execute(query);
}

App.prototype.OnSearchComplete = function() {
    var eos = 0;
    if (this.siteSearch.results && this.siteSearch.results.length > 0) {
	document.getElementById("content").innerHTML += "<ul>";
	for (var i = 0; i < this.siteSearch.results.length; i++) {
            var result = this.siteSearch.results[i];
	    try {
		var idx = result.url.lastIndexOf("/");
		var page = "";
		if (idx >= 0)
		    page = result.url.substr(idx);
		if (page != "/4") {
		    var h = "<li class='result'><a href='" + result.url + "'>" + result.title + "</a><p class='result'>" + result.content + "</p></li>";
		    document.getElementById("content").innerHTML += h;
		    this.resultCount++;
		}
	    }
	    catch(err) {
	    }
	}	
	document.getElementById("content").innerHTML += "</ul>";
	var cursor = this.siteSearch.cursor;
	if (cursor && cursor.currentPageIndex < cursor.pages.length - 1) {
	    this.siteSearch.gotoPage(cursor.currentPageIndex + 1);
	}
	else
	    eos = 1;
    }
    else
	eos = 1;
    
    if (eos) {
	var googleQuery = this.query + " site:http://wiki.tcl.tk";
	if (this.resultCount > 0) {
	    document.getElementById("searchprogress").innerHTML = "Search results for &quot;<b>" + this.query + "</b>&quot; - <span class='branding'>powered by <img class='branding' src='http://www.google.com/uds/css/small-logo.png'</img></span>";
	    document.getElementById("content").innerHTML += "<p><a class='googlesearch' target='_blank' href='http://www.google.com/search?q=" + URLencode(googleQuery) + "'>Click here to see all matches on Google Web Search</a></p>"
	}
	else {
	    document.getElementById("searchprogress").innerHTML = "No search results for &quot;<b>" + this.query + "</b>&quot;";
	}
    }
}

function googleQuery() {
    var app = new App(document.getElementById("googletxt").value);
    return false;
}
