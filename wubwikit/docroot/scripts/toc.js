function inittocpages(){
    document.getElementById('wrapper').style.marginLeft = '-160px';
    document.getElementById('content').style.marginLeft = '160px';
    document.getElementById('menu_area').style.display = 'inline';
    document.getElementById('searchform').style.display = 'inline';
}

function tocpages(){
    document.getElementById('wiki_menu').style.display='inline';
    document.getElementById('page_toc').style.display='inline';
    document.getElementById('wiki_toc').style.display='inline';
    document.getElementById('wrapper').style.marginLeft = '-160px';
    document.getElementById('content').style.marginLeft = '160px';
    document.getElementById('menu_area').style.display='inline';
}

function notocpages(){
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
    inittocpages();

    needs_toc=getCookie('wiki_toc');
    if (needs_toc==null || needs_toc=="" || needs_toc=="1") {
	tocpages();
    }
    else {
	notocpages();
    }
    try {
	document.getElementById("gsearchtxt").value;
	googleQuery();
    }
    catch (e){}
}

function toggleTOC()
{
    needs_toc=getCookie('wiki_toc')
    if (needs_toc==null || needs_toc=="" || needs_toc=="1") {
	notocpages();
	setCookie('wiki_toc', 0, 30, "/_toc/");
    } else {
	tocpages();
	setCookie('wiki_toc', 1, 30, "/_toc/");
    }
}
