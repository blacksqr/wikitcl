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
    page_toc();
    ajaxtocpage('/_toc', 'wiki_toc');
    document.getElementById('wrapper').style.marginLeft = '-160px';
    document.getElementById('content').style.marginLeft = '160px';
    document.getElementById('menu_area').style.display = 'inline';
    document.getElementById('searchform').style.display = 'inline';
    // document.getElementById('gsearchform').style.display = 'inline';
    document.getElementById('footer').innerHTML += ' &bull; ' + 
	    '<a href="javascript:toggleTOC();" id="toggle_toc">Hide menu</a>';
}

function ajaxtocpages(){
    document.getElementById('wiki_menu').style.display='inline';
    document.getElementById('page_toc').style.display='inline';
    document.getElementById('wiki_toc').style.display='inline';
    document.getElementById('wrapper').style.marginLeft = '-160px';
    document.getElementById('content').style.marginLeft = '160px';
    document.getElementById('toggle_toc').innerHTML = "Hide menu";
    document.getElementById('menu_area').style.display='inline';
}

function ajaxnotocpages(){
    document.getElementById('wiki_menu').style.display='none';
    document.getElementById('page_toc').style.display='none';
    document.getElementById('wiki_toc').style.display='none';
    document.getElementById('wrapper').style.marginLeft = '0';
    document.getElementById('wrapper').style.marginRight = '-5px';
    document.getElementById('content').style.marginLeft = '5px';
    document.getElementById('toggle_toc').innerHTML = "Show menu";
    document.getElementById('menu_area').style.display='none';
}

function setCookie(c_name,value,expiredays)
{
    var exdate=new Date();
    exdate.setDate(exdate.getDate()+expiredays);
    document.cookie=c_name+ "=" +escape(value)+
	((expiredays==null) ? "" : ";expires="+exdate.toGMTString())+
	";path=/";
}

function getCookie(c_name)
{
    if (document.cookie.length>0) {
	c_start=document.cookie.indexOf(c_name + "=");
	if (c_start!=-1) { 
	    c_start=c_start + c_name.length+1;
	    c_end=document.cookie.indexOf(";",c_start);
	    if (c_end==-1) c_end=document.cookie.length;
	    return unescape(document.cookie.substring(c_start,c_end));
	} 
    }
    return ""
}

function checkTOC()
{
    ajaxinittocpages();
    needs_toc=getCookie('witoc')
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
    needs_toc=getCookie('witoc')
    if (needs_toc==null || needs_toc=="" || needs_toc=="1") {
	ajaxnotocpages();
	setCookie('witoc', 0, 365);
    }
    else {
	ajaxtocpages();
	setCookie('witoc', 1, 365);
    }
}

function clearSearch() {
	var txt = document.getElementById('searchtxt');
	txt.style.color = 'black';
	txt.value = '';
}

function setSearch() {
	var txt = document.getElementById('searchtxt');
	txt.style.color = 'gray';
	if (txt.value == '') {
		txt.value = 'Search titles';
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
		txt.value = 'Search in pages';
	}
}

function URLencode(sStr) {
    return escape(sStr)
	.replace(/\+/g, '%2B')
	.replace(/\"/g,'%22')
	.replace(/\'/g, '%27');
}

function App(query) {
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
    document.getElementById("footer").innerHTML = "<a href='http://wiki.tcl.tk'>Home</a> &bull; <a href='/4'>Recent changes</a> &bull; <a href='/3'>Help</a> &bull; <a href='/2'>Search</a> &bull; <a href='javascript:toggleTOC();' id='toggle_toc'>Hide menu</a>";
    document.getElementById("content").innerHTML = "<div id='branding'>Powered by google</div>";
    GSearch.getBranding(document.getElementById("branding"));
    var googleQuery = query + "+site:http://wiki.tcl.tk";
    document.getElementById("content").innerHTML += "<p><a class='googlesearch' href='http://www.google.com/search?q=" + URLencode(googleQuery) + "'>Click here to see all matches on Google Web Search</a></p>";
    document.getElementById("content").innerHTML += "<p>Search results for &quot;<b>" + query + "</b>&quot; :</p>";
    this.siteSearch.execute(query);
}

App.prototype.OnSearchComplete = function() {
    if (this.siteSearch.results && this.siteSearch.results.length > 0) {
	document.getElementById("content").innerHTML += "<ul>";
	for (var i = 0; i < this.siteSearch.results.length; i++) {
            var result = this.siteSearch.results[i];
	    try {
		var h = "<li class='result'><a href='" + result.url + "'>" + result.title + "</a><p class='result'>" + result.content + "</p></li>";
		document.getElementById("content").innerHTML += h;
	    }
	    catch(err) {
	    }
	}	
	document.getElementById("content").innerHTML += "</ul>";
	var cursor = this.siteSearch.cursor;
	if (cursor && cursor.currentPageIndex < cursor.pages.length - 1) {
	    this.siteSearch.gotoPage(cursor.currentPageIndex + 1);
	}
    }
}

function googleQuery() {
    var app = new App(document.getElementById("googletxt").value);
    return false;
}
