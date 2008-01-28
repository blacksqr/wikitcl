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

// [Cookie] Gets a value from a cookie
function getCookie(cookieName) {
  var cookieValue = '';
  var posName = document.cookie.indexOf(escape(cookieName) + '=');
  if (posName != -1) {
    var posValue = posName + (escape(cookieName) + '=').length;
    var endPos = document.cookie.indexOf(';', posValue);
    if (endPos != -1)
      cookieValue = unescape(document.cookie.substring(posValue, endPos));
    else
      cookieValue = unescape(document.cookie.substring(posValue));
  }
  return (cookieValue);
};

function checkTOC()
{
    ajaxinittocpages();
    clearCookie('wikitoc', '/');	/* remove old cookie */
    clearCookie('witoc', '/');	/* remove old cookie */
    needs_toc=getCookie('witoc');
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
	setCookie('witoc', 0, 365, "/_cookies/");
    } else {
	ajaxtocpages();
	setCookie('witoc', 1, 365, "/_cookies/");
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
		txt.value = 'Search';
	}
}


