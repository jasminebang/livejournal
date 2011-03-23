// called by S2:
function setStyle (did, attr, val) {
    if (! document.getElementById) return;
    var de = document.getElementById(did);
    if (! de) return;
    if (de.style)
        de.style[attr] = val
}

// called by S2:
function setInner (did, val) {
    if (! document.getElementById) return;
    var de = document.getElementById(did);
    if (! de) return;
    de.innerHTML = val;
}

// called by S2:
function hideElement (did) {
    if (! document.getElementById) return;
    var de = document.getElementById(did);
    if (! de) return;
    de.style.display = 'none';
}

// called by S2:
function setAttr (did, attr, classname) {
    if (! document.getElementById) return;
    var de = document.getElementById(did);
    if (! de) return;
    de.setAttribute(attr, classname);
}

// called from Page:
function multiformSubmit (form, txt) {
    var sel_val = form.mode.value;
    if (!sel_val) {
        alert(txt.no_action);
        return false;
    }

    if (sel_val.substring(0, 4) == 'all:') { // mass action
        return;
    }

    var i = -1, has_selected = false; // at least one checkbox
    while (form[++i]) {
        if (form[i].name.substring(0, 9) == 'selected_' && form[i].checked) {
            has_selected = true;
            break;
        }
    }
    if (!has_selected) {
        alert(txt.no_comments);
        return false;
    }

    if (sel_val == 'delete' || sel_val == 'deletespam') {
        return confirm(txt.conf_delete);
    }
}

function getLocalizedStr( key, username ) {
    var str = "";
    if( key in Site.ml_text ) {
        str = Site.ml_text[ key ];
        str = str.replace( '%username%', username );
    }

    return str;
}

// hsv to rgb
// h, s, v = [0, 1), [0, 1], [0, 1]
// r, g, b = [0, 255], [0, 255], [0, 255]
function hsv_to_rgb (h, s, v)
{
    if (s == 0) {
	v *= 255;
	return [v,v,v];
    }

    h *= 6;
    var i = Math.floor(h);
    var f = h - i;
    var p = v * (1 - s);
    var q = v * (1 - s * f);
    var t = v * (1 - s * (1 - f));

    v = Math.floor(v * 255 + 0.5);
    t = Math.floor(t * 255 + 0.5);
    p = Math.floor(p * 255 + 0.5);
    q = Math.floor(q * 255 + 0.5);

    if (i == 0) return [v,t,p];
    if (i == 1) return [q,v,p];
    if (i == 2) return [p,v,t];
    if (i == 3) return [p,q,v];
    if (i == 4) return [t,p,v];
    return [v,p,q];
}

function deleteComment (ditemid, isS1, action) {
	action = action || 'delete';
	
	var curJournal = (Site.currentJournal !== "") ? (Site.currentJournal) : (LJ_cmtinfo.journal);

    var form = $('ljdelopts' + ditemid),
        todel = $('ljcmt' + ditemid),
        opt_delthread, opt_delauthor, is_deleted, is_error,
        pulse = 0,
		url = LiveJournal.getAjaxUrl('delcomment')+'?mode=js&journal=' + curJournal + '&id=' + ditemid;
    
	var postdata = 'confirm=1';
    if (form && action == 'delete') { 
    	if (form.ban && form.ban.checked) {
			postdata += '&ban=1';
		}
    	if (form.spam && form.spam.checked) {
			postdata += '&spam=1';
		}
    	if (form.delthread && form.delthread.checked) {
			postdata += '&delthread=1';
			opt_delthread = true;
		}
    	if (form.delauthor && form.delauthor.checked) {
        	postdata += '&delauthor=1';
        	opt_delauthor = true;
    	}
    } else if (action == 'markAsSpam') {
		opt_delauthor = opt_delthread = true;
		postdata += '&ban=1&spam=1&delthread=1&delauthor=1';
	} else if (action == 'unspam') {
		url = LiveJournal.getAjaxUrl('spamcomment')+'?mode=unspam&journal=' + curJournal + '&talkid=' + ditemid;
	}
	
    postdata += '&lj_form_auth=' + LJ_cmtinfo.form_auth;

    var opts = {
        url: url,
        data: postdata,
        method: 'POST',
        onData: function(data) {
            is_deleted = !!data;
            is_error = !is_deleted;
        },
        onError: function() {
          alert('Error deleting ' + ditemid);
          is_error = true;
        }
    };

    HTTPReq.getJSON(opts);

    var flash = function () {
        var rgb = hsv_to_rgb(0, Math.cos((pulse + 1) / 2), 1);
        pulse += 3.14159 / 5;
        var color = "rgb(" + rgb[0] + "," + rgb[1] + "," + rgb[2] + ")";

        todel.style.border = "2px solid " + color;
        if (is_error) {
            todel.style.border = "";
            // and let timer expire
        } else if (is_deleted) {
            removeComment(ditemid, opt_delthread, isS1);
            if (opt_delauthor) {
                for (var item in LJ_cmtinfo) {
                    if (LJ_cmtinfo[item].u == LJ_cmtinfo[ditemid].u) {
                        removeComment(item, false, isS1);
                    }
                }
            }
        } else {
            window.setTimeout(flash, 50);
        }
    };

    window.setTimeout(flash, 5);
}

function removeComment (ditemid, killChildren, isS1) {
    if(isS1){
		var threadId = ditemid;

		getThreadJSON(threadId, function(result) {
			for( var i = 0; i < result.length; ++i ){
				jQuery("#ljcmtxt" + result[i].thread).html( result[i].html );
				if( result[i].thread in ExpanderEx.Collection)
					ExpanderEx.Collection[ result[i].thread ] = result[i].html;
			}
		});
    }
    else {
        var todel = document.getElementById("ljcmt" + ditemid);
        if (todel) {
            todel.style.display = 'none';

            var userhook = window["userhook_delete_comment_ARG"];
            if (userhook)
                userhook(ditemid);
        }
    }
    if (killChildren) {
        var com = LJ_cmtinfo[ditemid];
        for (var i = 0; i < com.rc.length; i++) {
            removeComment(com.rc[i], true, isS1);
        }
    }
}

function createDeleteFunction(ae, dItemid, isS1, action) {
	action = action || 'delete';
	
    return function (e) {
		e = jQuery.event.fix(e || window.event);
		
		e.stopPropagation();
		e.preventDefault();

        var doIT = 0;
        // immediately delete on shift key
        if (e.shiftKey) {
			doIT = 1;
			deleteComment(dItemid, isS1, action);
			return true;
		}
		
		if (!LJ_cmtinfo) {
			return true;
		}

        var com = LJ_cmtinfo[dItemid],
			comUser = LJ_cmtinfo[dItemid].u,
			remoteUser = LJ_cmtinfo.remote;
        if (!com || !remoteUser) {
			return true;
		}
        var canAdmin = LJ_cmtinfo.canAdmin;
		
		if (action == 'markAsSpam') {
			if (!window.delPopup) {
				window.delPopup = jQuery('<div />')
					.delegate('input.spam-comment-button', 'click', function () {
						window.delPopup.bubble('hide');
					});
			}			
			
			window.delPopup
				.html('<div class="b-popup-group"><div class="b-popup-row b-popup-row-head"><strong>' + getLocalizedStr('comment.mark.spam.title', comUser) + '</strong></div><div class="b-popup-row">' + getLocalizedStr('comment.mark.spam.subject', comUser) + '</div><div class="b-popup-row"><input type="button" class="spam-comment-button" onclick="deleteComment(' + dItemid + ', ' + isS1 + ', \'' + action + '\');" value="' + getLocalizedStr('comment.mark.spam.button', comUser) + '"></div><div>', ae, e, 'spamComment' + dItemid)
				.bubble({
					toggleOnTargetClick: false
				})
				.bubble('show', ae);
			
			return true;
		} else if (action == 'delete') {
	        var inHTML = [ "<form id='ljdelopts" + dItemid + "'><div class='b-popup-group'><div class='b-popup-row b-popup-row-head'><strong>" + getLocalizedStr( 'comment.delete.q', comUser ) + "</strong></div>" ];
	        var lbl;
	        if (com.username !== "" && com.username != remoteUser && canAdmin) {
	            lbl = "ljpopdel" + dItemid + "ban";
	            inHTML.push("<div class='b-popup-row'><input type='checkbox' name='ban' id='" + lbl + "'> <label for='" + lbl + "'>" + getLocalizedStr( 'comment.ban.user', comUser ) + "</label></div>");
	        }
	
	        if (com.rc && com.rc.length && canAdmin) {
	            lbl = "ljpopdel" + dItemid + "thread";
	            inHTML.push("<div class='b-popup-row'><input type='checkbox' name='delthread' id='" + lbl + "'> <label for='" + lbl + "'>" + getLocalizedStr( 'comment.delete.all.sub', comUser ) + "</label></div>");
	        }
	        if (canAdmin&&com.username) {
	            lbl = "ljpopdel" + dItemid + "author";
	            inHTML.push("<div class='b-popup-row'><input type='checkbox' name='delauthor' id='" + lbl + "'> <label for='" + lbl + "'>" + getLocalizedStr( 'comment.delete.all', "<b>" + ( (com.username == remoteUser ? 'my' : comUser) ) + "</b>" ) + "</label></div>");
	        }
	
	        inHTML.push("<div class='b-popup-row'><input class='delete-comment-button' type='button' value='" + getLocalizedStr( 'comment.delete', comUser ) + "' onclick='deleteComment(" + dItemid + ", " + isS1.toString() + ");' /></div></div><div class='b-bubble b-bubble-alert b-bubble-noarrow'><i class='i-bubble-arrow-border'></i><i class='i-bubble-arrow'></i>" + getLocalizedStr( 'comment.delete.no.options', comUser ) + "</div></form>");
			
			if (!window.modPopup) {
				window.modPopup = jQuery('<div />')
					.delegate('input.delete-comment-button', 'click', function () {
						window.modPopup.bubble('hide');
					});
			}
			
			window.modPopup
				.html(inHTML.join(' '))
				.bubble({
					toggleOnTargetClick: false
				})
				.bubble('show', ae);
		} else if (action == 'unspam') {
			deleteComment(dItemid, isS1, action);
		}
	};
}

function poofAt (pos) {
    var de = document.createElement("div");
    de.style.position = "absolute";
    de.style.background = "#FFF";
    de.style.overflow = "hidden";
    var opp = 1.0;

    var top = pos.y;
    var left = pos.x;
    var width = 5;
    var height = 5;
    document.body.appendChild(de);

    var fade = function () {
        opp -= 0.15;
        width += 10;
        height += 10;
        top -= 5;
        left -= 5;

        if (opp <= 0.1) {
            de.parentNode.removeChild(de);
        } else {
            de.style.left = left + "px";
            de.style.top = top + "px";
            de.style.height = height + "px";
            de.style.width = width + "px";
            de.style.filter = "alpha(opacity=" + Math.floor(opp * 100) + ")";
            de.style.opacity = opp;
            window.setTimeout(fade, 20);
        }
    };
    fade();
}

function updateLink (ae, resObj, clickTarget) {
    ae.href = resObj.newurl;
    var userhook = window["userhook_" + resObj.mode + "_comment_ARG"];
    var did_something = 0;

    if (clickTarget && clickTarget.src && clickTarget.src == resObj.oldimage) {
        clickTarget.src = resObj.newimage;
        did_something = 1;
    }

    if (userhook) {
        userhook(resObj.id);
        did_something = 1;
    }

    // if all else fails, at least remove the link so they're not as confused
    if (! did_something) {
        if (ae && ae.style)
            ae.style.display = 'none';
        if (clickTarget && clickTarget.style)
            clickTarget.style.dispay = 'none';
    }

}

var tsInProg = {}  // dict of { ditemid => 1 }
function createModerationFunction(control, dItemid, isS1) {
	var comUser = LJ_cmtinfo[dItemid].u;	
	
	return function (e) {
		var	e = jQuery.event.fix(e || window.event),
			pos = { x: e.pageX, y: e.pageY },
			modeParam = LiveJournal.parseGetArgs(location.href).mode,
			hourglass;
			
		e.stopPropagation();
		e.preventDefault();
			
		sendModerateRequest();

		function sendModerateRequest() {
			var	bmlName = 'talkscreen',
				postUrl = control.href.replace(new RegExp('.+' + bmlName + '\.bml'), LiveJournal.getAjaxUrl(bmlName)),
				postParams = { 'confirm': 'Y', lj_form_auth: LJ_cmtinfo.form_auth };
				
			hourglass = jQuery(e).hourglass()[0];
			
			jQuery.post(postUrl, postParams, function (json) {
				tsInProg[dItemid] = 0;
				
				if (isS1) {
					handleS1();
				} else {
					var ids = checkRcForNoCommentsPage(json);
					handleS2(ids);
				}				
			});		
		}
		
		function handleS1() {
			var newNode, showExpand, j, children,
				threadId = dItemid,
				threadExpanded = !!(LJ_cmtinfo[ threadId ].oldvars && LJ_cmtinfo[ threadId ].full);
				populateComments = function (result) {
					for( var i = 0; i < result.length; ++i ){
						if( LJ_cmtinfo[ result[i].thread ].full ){
							showExpand = !( 'oldvars' in LJ_cmtinfo[ result[i].thread ]);
	
							//still show expand button if children comments are folded
							if( !showExpand ) {
								children  = LJ_cmtinfo[ result[i].thread ].rc;
	
								for( j = 0; j < children.length;  ++j ) {
									if( !( 'oldvars' in LJ_cmtinfo[ children[j] ] ) ) {
										showExpand = true;
									}
								}
							}
							
							if (!result[i].html) {
								removeEmptyMarkup(result[i].thread);
							}
	
							newNode = ExpanderEx.prepareCommentBlock(
									result[i].html || '',
									result[i].thread || '',
									showExpand
							);
	
							setupAjax( newNode[0], isS1 );
							
							jQuery("#ljcmtxt" + result[i].thread).replaceWith( newNode );
						}
					}
					hourglass.hide();
					poofAt(pos);
				};
	
			getThreadJSON(threadId, function (result) {
				//if comment is expanded we need to fetch it's collapsed state additionally
				if( threadExpanded && LJ_cmtinfo[ threadId ].oldvars.full )
				{
					getThreadJSON( threadId, function (result2) {
						ExpanderEx.Collection[ threadId ] = ExpanderEx.prepareCommentBlock( result2[0].html, threadId, true ).html();
						populateComments( result );
					}, true, true );
				}
				else
					populateComments( result );
			}, false, !threadExpanded);			
		}

		function handleS2(ids) {
			// modified jQuery.fn.load
			jQuery.ajax({
				url: location.href,
				type: 'GET',
				dataType: 'html',
				complete: function (res, status) {
					// If successful, inject the HTML into all the matched elements
					if (status == 'success' || status == 'notmodified') {
						// Create a dummy div to hold the results
						var nodes = jQuery('<div/>')
							// inject the contents of the document in, removing the scripts
							// to avoid any 'Permission Denied' errors in IE
							.append(res.responseText.replace(/<script(.|\s)*?\/script>/gi, ''))
							// Locate the specified elements
							.find(ids)
							.each(function () {
								var id = this.id.replace(/[^0-9]/g, '');
								if (LJ_cmtinfo[id].expanded) {
									var expand = this.innerHTML.match(/Expander\.make\(.+?\)/)[0];
									(function(){
										eval(expand);
									}).apply(document.createElement('a'));
								} else {
									jQuery('#' + this.id).replaceWith(this);
									setupAjax(this, isS1);
								}
							});
						hourglass.hide();
						poofAt(pos);
					}
				}
			});			
		}
		
		function checkRcForNoCommentsPage() {
			var commsArray = [ dItemid ], ids;
			
			// check rc for no comments page
			if (LJ_cmtinfo[dItemid].rc) {
				if (/mode=(un)?freeze/.test(control.href)) {
					mapComms(dItemid);
				}
				ids = '#ljcmt' + commsArray.join(',#ljcmt');
			} else {
				var rpcRes;
				eval(json);
				updateLink(control, rpcRes, control.getElementsByTagName('img')[0]);
				// /tools/recent_comments.bml
				if (document.getElementById('ljcmtbar'+dItemid)) {
					ids = '#ljcmtbar' + dItemid;
				}
				// ex.: portal/
				else {
					hourglass.hide();
					poofAt(pos);
					return;
				}
			}
			
			
			function mapComms(id) {
				var i = -1, newId;
				
				while (newId == LJ_cmtinfo[id].rc[++i]) {
					if (LJ_cmtinfo[newId].full) {
						commsArray.push(newId);
						mapComms(String(newId));
					}
				}
			}
			
			return ids;
		}
		
		return false;
	}
}

function removeEmptyMarkup(threadId) {
	jQuery('#ljcmt' + threadId).remove();	
}

function setupAjax (node, isS1) {
    var links = node ? node.getElementsByTagName('a') : document.links,
        rex_id = /id=(\d+)/,
        i = -1, ae;

    isS1 = isS1 || false;
    while (links[++i]) {
        ae = links[i];
        if (ae.href.indexOf('talkscreen.bml') != -1) {
            var reMatch = rex_id.exec(ae.href);
            if (!reMatch) continue;

            var id = reMatch[1];
            if (!document.getElementById('ljcmt' + id)) continue;

            ae.onclick = createModerationFunction(ae, id, isS1);
        } else if (ae.href.indexOf('delcomment.bml') != -1) {
            if (LJ_cmtinfo && LJ_cmtinfo.disableInlineDelete) continue;

            var reMatch = rex_id.exec(ae.href);
            if (!reMatch) continue;

            var id = reMatch[1];
            if (!document.getElementById('ljcmt' + id)) continue;
			
			var action = (ae.href.indexOf('spam=1') != -1) ? 'markAsSpam' : 'delete';

			ae.onclick = createDeleteFunction(ae, id, isS1, action);
		// unspam
		} else if (ae.href.indexOf('spamcomment.bml') != -1) {
            var reMatch = rex_id.exec(ae.href);
            if (!reMatch) continue;

            var id = reMatch[1];
            if (!document.getElementById('ljcmt' + id)) continue;
			
			ae.onclick = createDeleteFunction(ae, id, isS1, 'unspam');
		}
    }
}

function getThreadJSON(threadId, success, getSingle)
{
    var postid = location.href.match(/\/(\d+).html/)[1],
		modeParam = LiveJournal.parseGetArgs(location.href).mode,
        params = [
            'journal=' + Site.currentJournal,
            'itemid=' + postid,
            'thread=' + threadId,
            'depth=' + LJ_cmtinfo[ threadId ].depth
        ];
		
    if (getSingle)
        params.push( 'single=1' );
		
	if (modeParam)
		params.push( 'mode=' + modeParam )

    var url = LiveJournal.getAjaxUrl('get_thread') + '?' + params.join( '&' );
    jQuery.get( url, success, 'json' );
}

jQuery(function(){setupAjax( false, ("is_s1" in LJ_cmtinfo ) )});
