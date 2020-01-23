//# sourceURL=J_SiteSensor1_UI7.js
/**
 * J_SiteSensor_UI7.js
 * Configuration interface for SiteSensor
 *
 * Copyright 2016,2017,2019 Patrick H. Rigney, All Rights Reserved.
 * This file is part of Reactor. For license information, see LICENSE at https://github.com/toggledbits/SiteSensor
 */
/* globals api,Utils,jQuery,$ */
/* jshint multistr: true */

//"use strict"; // fails on UI7, works fine with ALTUI

var SiteSensor = (function(api, $) {

	var pluginVersion = "1.15";

	// unique identifier for this plugin...
	var uuid = '32f7fe60-79f5-11e7-969f-74d4351650de';

	var serviceId = "urn:toggledbits-com:serviceId:SiteSensor1";

	var myModule = {};

	var isVisible = false;
	var isOpenLuup = false;
	// var isALTUI = false;
	var needsReload = false;

	/* Recipe variables. Exprn are handled separately. */
	var recipeVars = [ "RequestURL", "Headers", "Interval", "Timeout", "QueryArmed",
					   "ResponseType", "Trigger", "NumExp", "TripExpression", "ArmedInterval",
					   "EvalInternal" ];

	function updateResponseFields() {
		var rtype = jQuery('select#rtype').val();
		jQuery('select#trigger option[value="match"]').attr('disabled', rtype != "text");
		jQuery('select#trigger option[value="neg"]').attr('disabled', rtype != "text");
		jQuery('select#trigger option[value="expr"]').attr('disabled', rtype != "json");

		// If the currently selected trigger value is disabled, select the first enabled one.
		var ttype = jQuery('select#trigger').val();
		if ( ttype === undefined || ttype === null || jQuery('select#trigger option[value="' + ttype + '"]').attr('disabled') ) {
			ttype = jQuery('select#trigger option:enabled').first().val();
			jQuery('select#trigger').val(ttype).change(); /* causes recursion */
		}

		jQuery('input#pattern').attr('disabled', ttype != "match" && ttype != "neg");
		jQuery('input#tripexpression').attr('disabled', ttype != "expr");

		jQuery('div.tb-textcontrols').css('display', rtype == "text" ? "block" : "none");
		jQuery('div.tb-jsoncontrols').css('display', rtype == "json" ? "block" : "none");
	}

	function onBeforeCpanelClose(args) {
		// console.log('handler for before cpanel close');
		isVisible = false;
		if ( needsReload && confirm( "Since you changed device type configuration, Luup needs to be reloaded for those changes to take effect. Click 'OK' to reload now, or 'Cancel' to do it yourself later.") ) {
			api.performActionOnDevice( 0, "urn:micasaverde-com:serviceId:HomeAutomationGateway1", "Reload",
				{ actionArguments: { Reason: "SiteSensor device changes require reload" } } );
		}
		needReload = false;
	}

	function initPlugin() {
		var ud = api.getUserData();
		for (var i=0; i < ud.devices.length; ++i ) {
			if ( ud.devices[i].device_type == "openLuup" && ud.devices[i].id_parent == 0 ) {
				isOpenLuup = true;
				break;
			}
		}

		needsReload = false;
	}

	function configurePlugin()
	{
		try {
			initPlugin();

			var myDevice = api.getCpanelDeviceId();

			var html = "";

			html += "<style>";
			html += ".tb-cgroup { padding: 0px 32px 0px 0px }";
			html += "</style>";

			// Request URL
			html += "<div class=\"tb-cgroup pull-left\">";
			html += "<h2>Request URL</h2><label for=\"requestURL\">Enter the URL to be queried:</label><br/>";
			html += "<textarea type=\"text\" rows=\"3\" cols=\"64\" wrap=\"soft\" id=\"requestURL\" />";
			html += "</div>";

			// Request Headers
			html += "<div class=\"tb-cgroup pull-left\">";
			html += "<h2>Request Headers</h2><label for=\"requestHeaders\">Enter request headers, one per line:</label><br/>";
			html += "<textarea type=\"text\" rows=\"3\" cols=\"64\" wrap=\"soft\" id=\"requestHeaders\" />";
			html += "</div>";

			html += "<div class=\"clearfix\"></div>";

			// Request interval
			html += "<div class=\"tb-cgroup pull-left\">";
			html += "<h2>Request Interval</h2><label for=\"timeout\">Enter the number of seconds between requests:</label><br/>";
			html += "<input type=\"text\" size=\"5\" maxlength=\"5\" class=\"numfield\" id=\"interval\" />";
			html += " <input type=\"checkbox\" value=\"1\" id=\"queryarmed\">&nbsp;Query only when armed";
			html += "</div>";

			html += "<div class=\"tb-cgroup pull-left\">";
			html += "<h2>Request Timeout</h2><label for=\"timeout\">Timeout (seconds):</label><br/>";
			html += "<input type=\"text\" size=\"5\" maxlength=\"5\" class=\"numfield\" id=\"timeout\" />";
			html += "</div>";

			html += "<div class=\"clearfix\"></div>";

			// Response Type
			html += "<div class=\"tb-cgroup pull-left\">";
			html += "<h2>Response Type</h2><label for=\"rtype\">Server response is handled as:</label><br/>";
			html += '<select id="rtype"><option value="text">Generic (text)</option>';
			html += '<option value="json">JSON data</option>';
			html += '</select>';
			html += "</div>";

			// Trigger
			html += "<div class=\"tb-cgroup pull-left\">";
			html += "<h2>Trigger Type</h2><label for=\"trigger\">Sensor is triggered when:</label><br/>";
			html += '<select id="trigger"><option value="err">URL unreachable or server replies with error</option>';
			html += '<option value="match">Response matches pattern</option>';
			html += '<option value="neg">Response does not match pattern</option>';
			html += '<option value="expr">The result of an expression is true</option>';
			html += '</select>';
			html += "</div>";

			html += "<div class=\"clearfix\"></div>";

			// Response pattern
			html += '<div class="tb-textcontrols">';
			html += "<h2>Response Pattern</h2><label for=\"pattern\">Enter the pattern to match in the response (note: not a regexp):</label><br/>";
			html += "<input type=\"text\" size=\"64\" id=\"pattern\" />";
			html += "</div>";

			// Trip Expression
			html += '<div class="tb-jsoncontrols">';
			html += "<h2>Trip Expression</h2><label for=\"tripexpression\">If the Trigger Type (above) is 'result of an expression', enter the expression below (true result=triggered):</label><br/>";
			html += "<input type=\"text\" size=\"64\" id=\"tripexpression\" />";

			// Expressions for drawing out field values
			var numexp = parseInt( api.getDeviceState( myDevice, serviceId, "NumExp" ) || 8 );
			if ( isNaN( numexp ) ) {
				numexp = 8;
			}
			html += "<h2>Value Expressions</h2>";
			html += "<p>Use these expressions to draw values from the response JSON data and store them in state variables. You can use these values as triggers for scenes and Lua scripts.";
			html += " You can also push the expression values out to virtual sensors (created children of this SiteSensor) for use with scene triggers, Reactor, etc. <span id='openluupvirtual'/>";
			html += "</p>";
			html += "<ol>";
			for (var ix=1; ix<=numexp; ix += 1) {
				html += '<li><input class="jsonexpr" id="expr' + ix + '" size="64" type="text">';
				html += ' Child sensor: <select class="childtype" id="child' + ix + '"><option value="">(none)</option></select>';
				html += '</li>';
			}
			html += "</ol>";

			html += '<p>The JSON data is encapsulated within a "response" key, so if your JSON data looks like the example below, the value <i>errCode</i> would be accessed by the expression <tt>response.errCode</tt>, while the value of <i>name</i> within the <i>type</i> key would be accessed using <tt>response.type.name</tt>. Refer to the <a href="https://www.toggledbits.com/sitesensor" target="_blank">plug-in documentation</a> for more details. Since SiteSensor uses <a href="https://www.toggledbits.com/luaxp" target="_blank">LuaXP</a> to evaluate expressions, you can also look at its <a href="https://www.toggledbits.com/luaxp/expressions" target="_blank">expression syntax</a> and <a href="https://www.toggledbits.com/luaxp/functions" target="_blank">built-in function reference</a> for guidance.</p>';
			html += "<code>{\n    \"errCode\": 0,\n    \"type\": {\n        \"name\": \"Normal\",\n        \"class\": \"apiobject\"\n    }\n}</code>";

			html += "<h2>Options</h2>";
			html += '<label for="reeval">Re-evaluate the expressions</label>&nbsp;<select id="reeval"><option value="">only immediately after requests (default)</option>';
			html += '<option value="60">every minute</option>';
			html += '</select>';
			html += '<br/>If you have expressions comparing API responses to the current time and date, it is recommended that you re-evaluate them between requests and make your Request Interval longer. This avoids spamming the remote API with requests for data that rarely changes, but still gives you fast response to time-triggered events.';

			html += "</div>"; // tb-jsoncontrols

			html += '<hr><p><b>Find SiteSensor useful?</b> Please consider supporting the project with <a href="https://www.toggledbits.com/donate">a small donation</a>. I am grateful for any support you choose to give!</p>';

			// Push generated HTML to page
			api.setCpanelContent(html);

			// Restore values
			var s;
			s = api.getDeviceState(myDevice, serviceId, "RequestURL");
			jQuery("#requestURL").val(s ? s : "").change( function( obj ) {
				var newUrl = jQuery(this).val().trim();
				api.setDeviceStatePersistent(myDevice, serviceId, "RequestURL", newUrl, 0);
			});

			s = api.getDeviceState(myDevice, serviceId, "Headers");
			if (s) {
				// decode
				s = s.replace(/\|/g, "\n"); /* list breaks back to newlines */
				s = s.replace(/%(..)/g, function( m, p1 ) { return String.fromCharCode(Number.parseInt(p1,16)); } ); /* restore escaped */
			}
			jQuery("#requestHeaders").val(s ? s : "").change( function( obj ) {
				var newText = jQuery(this).val();
				// encode
				newText = newText.trim();
				newText = newText.replace(/([|%])/g, function( m ) { return "%" + m.charCodeAt(0).toString(16); } ); /* escape our separator and escape */
				newText = newText.replace(/\s*(\r|\n|\r\n)/g, "|"); /* Convert newlines to our list breaks */
				api.setDeviceStatePersistent(myDevice, serviceId, "Headers", newText, 0);
			});

			s = parseInt(api.getDeviceState(myDevice, serviceId, "Interval"));
			if (isNaN(s))
				s = 1800;
			jQuery("input#interval").val(s).change( function( obj ) {
				var newInterval = jQuery(this).val().trim();
				if (newInterval.match(/^[0-9]+$/) && newInterval > 0)
					api.setDeviceStatePersistent(myDevice, serviceId, "Interval", newInterval, 0);
			});

			s = parseInt(api.getDeviceState(myDevice, serviceId, "QueryArmed"));
			if (isNaN(s))
				s = 1;
			if (s != 0) jQuery("input#queryarmed").prop("checked", true);
			jQuery("input#queryarmed").change( function( obj ) {
				var newState = jQuery(this).prop("checked");
				api.setDeviceStatePersistent(myDevice, serviceId, "QueryArmed", newState ? "1" : "0", 0);
			});

			s = parseInt(api.getDeviceState(myDevice, serviceId, "Timeout"));
			if (isNaN(s))
				s = 60;
			jQuery("input#timeout").val(s).change( function( obj ) {
				var newVal = jQuery(this).val().trim();
				if (newVal.match(/^[0-9]+$/) && newVal > 0) {
					api.setDeviceStatePersistent(myDevice, serviceId, "Timeout", newVal, 0);
				}
			});

			s = api.getDeviceState(myDevice, serviceId, "ResponseType");
			if (s) jQuery('select#rtype option[value="' + s + '"]').prop('selected', true);
			jQuery('select#rtype').change( function( obj ) {
				var newType = jQuery(this).val();
				api.setDeviceStatePersistent(myDevice, serviceId, "ResponseType", newType, 0);
				updateResponseFields();
			});

			s = api.getDeviceState(myDevice, serviceId, "Trigger");
			if (s) jQuery('select#trigger option[value="' + s + '"]').prop('selected', true);
			jQuery('select#trigger').change( function( obj ) {
				var newType = jQuery(this).val();
				api.setDeviceStatePersistent(myDevice, serviceId, "Trigger", newType, 0);
				updateResponseFields();
			});

			s = api.getDeviceState(myDevice, serviceId, "Pattern");
			jQuery("input#pattern").val(s ? s : "").change( function( obj ) {
				var newPat = jQuery(this).val().trim();
				api.setDeviceStatePersistent(myDevice, serviceId, "Pattern", newPat, 0);
			});

			s = api.getDeviceState(myDevice, serviceId, "TripExpression");
			jQuery("input#tripexpression").val(s ? s : "").change( function( obj ) {
				var newExpr = jQuery(this).val().trim();
				api.setDeviceStatePersistent(myDevice, serviceId, "TripExpression", newExpr, 0);
			});

			s = api.getDeviceState(myDevice, serviceId, "EvalInterval");
			if (s) {
				// If the currently selected option isn't on the list, add it, so we don't lose it.
				var el = jQuery('select#reeval option[value="' + s + '"]');
				if ( el.length == 0 ) {
					jQuery('select#reeval').append($('<option>', { value: s }).text('Every ' + s + ' seconds (custom)').prop('selected', true));
				} else {
					el.prop('selected', true);
				}
			}
			jQuery("select#reeval").change( function( obj ) {
				var newVal = jQuery(this).val();
				api.setDeviceStatePersistent(myDevice, serviceId, "EvalInterval", newVal, 0);
			});

			jQuery.ajax({
				url: api.getDataRequestURL(),
				data: {
					id: "lr_SiteSensor",
					action: "getvtypes"
				},
				dataType: "json",
				timeout: 5000
			}).done( function( data, statusText, jqXHR ) {
				var hasOne = false;
				var childMenu = jQuery( '<select/>' );
				for ( var ch in data ) {
					if ( data.hasOwnProperty( ch ) ) {
						childMenu.append( jQuery( '<option/>' ).val( ch ).text( data[ch].name || ch ) );
						hasOne = hasOne || ch != "urn:schemas-upnp-org:device:BinaryLight:1";
					}
				}
				if ( ! hasOne ) {
					jQuery( 'span#openluupvirtual' ).append( ' <b>Additional resources are required to be installed for openLuup. Please refer to <a href="https://github.com/toggledbits/SiteSensor" target="_blank">the GitHub repository for documentation</a>.</b>' );
				}
				childMenu = childMenu.children();
				jQuery( 'select.childtype' ).append( childMenu ).on( 'change.sitesensor', function( ev ) {
					var el = jQuery( ev.currentTarget );
					var id = el.attr( 'id' ).substr( 5 );
					api.setDeviceStatePersistent( api.getCpanelDeviceId(), serviceId, "Child" + id, el.val() || "" );
					needsReload = true;
				});
				jQuery( 'input.jsonexpr' ).each( function( obj ) {
					var ix = jQuery( this ).attr('id').substr(4);
					var s = ( api.getDeviceState(myDevice, serviceId, "Expr" + ix) || "" ).trim();
					jQuery( this ).val(s);
					var typ = api.getDeviceState(myDevice, serviceId, "Child" + ix) || "";
					jQuery( 'select#child' + ix + '.childtype' ).val( typ ).prop( 'disabled', "" === s );
				});
				jQuery( 'input.jsonexpr' ).change( function( obj ) {
					var newExpr = ( jQuery(this).val() || "" ).trim();
					var ix = jQuery(this).attr('id').substr(4);
					api.setDeviceStatePersistent(myDevice, serviceId, "Expr" + ix, newExpr, 0);
					if ( "" === newExpr ) {
						jQuery( 'select#child' + ix + '.childtype' ).val( "" ).change().prop( 'disabled', true );
					} else {
						jQuery( 'select#child' + ix + '.childtype' ).prop( 'disabled', false );
					}
				});
			}).fail( function( jqXHR ) {
				jQuery( 'select.childtype' ).prop( 'disabled', true );
				alert( "There was an error loading configuration data. Vera may be busy; try again in a moment." );
			});

			updateResponseFields();
		}
		catch (e)
		{
			Utils.logError('Error in SiteSensor.configurePlugin(): ' + e);
		}
	}

	function ipath( i ) {
		return 'https://www.toggledbits.com/assets/sitesensor/' + i + '.png';
	}

	function itag( i ) {
		var id = i.replace(/-(off|on)$/i, "");
		return '<img src="' + ipath( i ) + '" id="' + id + '" alt="' + id + '">';
	}

	function updateIndicators() {
		var devNum = api.getCpanelDeviceId();

		// Set up defaults and (re)actions
		var st = api.getDeviceStateVariable(devNum, "urn:toggledbits-com:serviceId:SiteSensor1", "Failed");
		jQuery("div#sitesensor-status img#status-indicator-caution").attr('src', st == "0" ? ipath("status-indicator-caution-off") : ipath("status-indicator-caution-on"));
		st = api.getDeviceStateVariable(devNum, "urn:micasaverde-com:serviceId:SecuritySensor1", "Armed");
		jQuery("div#sitesensor-status img#status-indicator-armed").attr('src', st == "0" ? ipath("status-indicator-armed-off") : ipath("status-indicator-armed-on"));
		st = api.getDeviceStateVariable(devNum, "urn:micasaverde-com:serviceId:SecuritySensor1", "Tripped");
		jQuery("div#sitesensor-status img#status-indicator-tripped").attr('src', st == "0" ? ipath("status-indicator-tripped-off") : ipath("status-indicator-tripped-on"));

		st = api.getDeviceStateVariable(devNum, "urn:toggledbits-com:serviceId:SiteSensor1", "LogRequests");
		if ( st == "0" ) {
			jQuery("div#sitesensor-log").hide();
		} else {
			jQuery("div#sitesensor-log").show();
			st = api.getDeviceStateVariable(devNum, "urn:toggledbits-com:serviceId:SiteSensor1", "LogCapture");
			st = st.replace(/[|]/g, "\n");
			jQuery("div#sitesensor-log textarea").val(st);
		}

		/* Periodic refresh */
		setTimeout( updateIndicators, 1000 );
	}

	function controlPanel() {
		try {
			var html = "";

			var devNum = api.getCpanelDeviceId();

			var st = api.getDeviceStateVariable(devNum, "urn:toggledbits-com:serviceId:SiteSensor1", "HideStatusIndicator");
			if ( st == "1" || st == "true" ) {
				return;
			}

			html += '<div id="sitesensor-status" style="width: 418px; margin: auto; border: groove 5px #999999;">' +
				itag("status-left") +
				itag("status-indicator-caution-on") +
				itag("status-indicator-armed-off") +
				itag("status-indicator-tripped-off") +
				itag("status-right") +
				'</div>';

			html += '<div id="sitesensor-log" style="width: 630px; margin: auto; padding-top: 8px;"><textarea wrap="off" style="width: 100%; height: 146px; padding: 4px 4px 4px 4px; background-color: #f8f8f8; font-family: monospace; font-size: 12px;"></textarea>';

			// Push generated HTML to page
			api.setCpanelContent(html);

			isVisible = true;

			api.registerEventHandler('on_ui_cpanel_before_close', SiteSensor, 'onBeforeCpanelClose');

			updateIndicators();
		} catch (e) {
			Utils.logError("Error in SiteSensor1.controlPanel(): " + e);
		}
	}

	function handleRecipeChange( ev ) {
		var $el = $("#origdata");
		$('textarea#loadrecipe').empty();
		$('button#applyrecipe').prop('disabled',true);
		var recipe = $el.val();
		var lines = [];
		try {
			var data = JSON.parse( recipe );
			if ( String( data.name || "" ).match( /^\s*$/ ) ) { throw "Field 'name' is required for recipe name"; }
			if ( String( data.version || "" ).match( /^\s*$/ ) ) { throw "Field 'version' is required"; }
			if ( String( data.author || "" ).match( /^\s*$/ ) ) { throw "Field 'author' is required"; }
			data.timestamp = Date.now();
			var blk = btoa( recipe );
			lines.push( "=== Ident: " + data.name + " version " + data.version + " by " +
				data.author + "; " +
				String(data.description||"").replace( /[\x00-\x1f\x7f-\x9f\u2028\u2029]/g, "" ) );
			lines.push( "=== BEGIN SITESENSOR RECIPE ===" );
			while ( blk.length > 76 ) {
				lines.push( blk.substring( 0, 76 ) );
				blk = blk.substring( 76 );
			}
			lines.push( blk );
			lines.push( "=== END SITESENSOR RECIPE ===" );
		} catch (ex) {
			lines.push( "*** INVALID CONFIGURATION -- SEE BELOW ***");
			lines.push(String(ex));
			var m = ex.toString().match( /at position (\d+)/ );
			if ( m ) {
				var at = parseInt( m[1] );
				var p1 = Math.max( 0, at-16 );
				var p2 = Math.min( at+16, recipe.length );
				lines.push( recipe.substring( p1, p2 ) );
			}
		}
		$("#blockdata").val( lines.join( "\n" ) );
	}

	function makeCurrentRecipe( myid ) {
		var val;
		var name = api.getDeviceAttribute( myid, "name" ) || myid;
		var data = { "name":name, "author": "", version: "", description: "", config:{} };
		data.version = Math.floor( Date.now() / 1000 );
		var nvars = recipeVars.length;
		for ( var ix=0; ix<recipeVars.length; ix++ ) {
			val = api.getDeviceState( myid, serviceId, recipeVars[ix] ) || "";
			if ( !val.match( /^\s*$/ ) ) {
				data.config[recipeVars[ix]] = val;
			}
		}
		data.source = api.getDeviceState( myid, serviceId, "Version" ) || 0;
		var numexp = parseInt( data.config.NumExp ) || 8;
		for ( ix=1; ix<=numexp; ix++ ) {
			var exname = "Expr" + ix;
			val = api.getDeviceState( myid, serviceId, exname ) || "";
			if ( !val.match( /^\s*$/ ) ) {
				data.config[exname] = val;
			}
		}
		var recipe = JSON.stringify( data, null, 4 );
		$( '#origdata' ).val( recipe );
		handleRecipeChange();
	}

	function handleApply() {
		if ( confirm( "Applying this recipe will overwrite this SiteSensor's configuration. OK?" ) ) {
			var $el = $( 'textarea#loadrecipe' );
			var recipe = $el.val() || "";
			var p1 = recipe.replace( /[\r\n]/g, "" ).match( /=== BEGIN SITESENSOR RECIPE ===(.*)=== END SITESENSOR RECIPE ===/im );
			var blk = atob( p1[1] );
			var data = JSON.parse( blk );
			var devnum = api.getCpanelDeviceId();
			/* Make a list of all variables we need */
			var found = {};
			for ( var ix=0; ix<recipeVars.length; ++ix ) { found[recipeVars[ix]] = true; }
			for ( var vname in data.config ) {
				/* Don't set any variables we don't know about */
				if ( data.config.hasOwnProperty( vname ) && found[vname] ) {
					delete found[vname]; /* mark */
					api.setDeviceStateVariablePersistent( devnum, serviceId, vname, data.config[vname], {
						onSuccess: function() {},
						onFailure: function() {}
					} );
				}
			}
			/* Clear any variables we need that the config didn't have */
			for ( vname in found ) {
				if ( found.hasOwnProperty( vname ) ) {
					console.log("Clearing "+vname+"; not in recipe");
					api.setDeviceStateVariablePersistent( devnum, serviceId, vname, "" );
				}
			}
			/* Get the expressions */
			var numexp = parseInt( data.config.NumExp ) || 8;
			for ( ix=1; ix<numexp; ++ix ) {
				vname = "Expr" + ix;
				api.setDeviceStateVariablePersistent( devnum, serviceId, vname, data.config[vname] || "" );
			}
			/* Done! */
			$( '.recipealert' ).text("Recipe applied!");
			$( '#origdata' ).val( JSON.stringify( data, null, 4 ) );
			handleRecipeChange();
		}
	}

	function handleLoadChange() {
		var $el = $( 'textarea#loadrecipe' );
		var recipe = $el.val() || "";
		var p1 = recipe.replace( /[\r\n]/g, "" ).match( /=== BEGIN SITESENSOR RECIPE ===(.*)=== END SITESENSOR RECIPE ===/i );
		var msg = "Invalid block.";
		if ( p1 ) {
			try {
				var blk = atob( p1[1] );
				var data = JSON.parse( blk );
				$( 'button#applyrecipe' ).prop( 'disabled', false );
				$( '.recipealert' ).text( "Ready to apply " + String(data.name) + " version " +
					String( data.version ) +
					". This will overwrite the current configuration of this SiteSensor!" );
				var recv = parseInt( data.source ) || 0;
				var sysv = parseInt( api.getDeviceState( api.getCpanelDeviceId(), serviceId, "Version" ) ) || 0;
				if ( recv > sysv ) {
					$( '.recipealert' ).append("<strong>&bull; Note: this recipe was made by a later version of SiteSensor. It may not be fully compatible with the version you are using.</strong>");
				}
				return;
			} catch (ex) {
				console.log(ex);
			}
		} else if ( recipe.match( /^\s*$/ ) ) {
			msg = "";
		} else {
			msg = "Invalid block. Make sure you keep the header and footer strings with the pasted block.";
		}
		$( 'button#applyrecipe' ).prop( 'disabled', true );
		$( '.recipealert' ).text( msg );
	}

	function doRecipe( myid ) {
		api.setCpanelContent( '<style>\
textarea#loadrecipe { font-family: monospace; width: 100%; height: 6em; } \
textarea#origdata { width: 100%; font-family: monospace; min-height: 20em; outline: none; } \
textarea#blockdata { width: 100%; font-family: monospace; height: 6em; outline: none; } \
</style> \
<div class="sise-recipe"> \
	<h2>Load a Recipe</h2> \
	<p>Recipes are pre-packaged configurations that you can load quickly. To load a recipe, paste it into the box below. You\'ll be asked to confirm the recipe content before it is applied to this SiteSensor.</p> \
	<textarea id="loadrecipe" placeholder="Paste the recipe here"></textarea> \
	<div class="recipealert" />\
	<div id="loadcontrol"><button id="applyrecipe" class="btn btn-sm btn-warning">Apply This Recipe</button></div> \
	<hr/>\
	<h2>Create a Recipe</h2> \
	<p>Have you made a SiteSensor configuration from which others may benefit? You can share this SiteSensor\'s configuration with others by creating a recipe. \
	   <b>Edit the configuration below to remove any authorization keys or other sensitive data. Do not remove any key/value pairs, but you can leave the value blank (no data between quotes) if you must.</b> \
	This editing does not change this SiteSensor"s configuration. As you edit, the block data representation \
	below will be updated. When you are satisfied with your edits, you can select and copy the \
	block data representation--<em>that</em> is the recipe you publish. Try not to break the JSON formatting of this configuration data. If you do, an error message will be shown below to help guide you to a fix; sometimes pasting the broken configuration into <a href="http://www.jsonlint.com/" target="_blank">jsonlint.com</a> will also help.</p><p>Hint: This is also a really good way to back up a SiteSensor configurations &mdash; you don\'t have to publish your recipes.</p></p><br/> \
	<textarea id="origdata" wrap="off"></textarea> \
	<p>Below is the block data representation -- this is what you publish.</p> \
	<textarea id="blockdata"></textarea></div> \
</div><hr/><div class="sise-footer">Thanks for using SiteSensor!</div>' );

		$( 'button#applyrecipe' ).prop( 'disabled', true )
			.on( "click", handleApply );

		$( 'textarea#loadrecipe' ).on( "change", handleLoadChange )
			.on( "input", handleLoadChange );

		$( '#origdata' )
			.on( "input", handleRecipeChange )
			.on( "change", handleRecipeChange );

		$( '#blockdata' )
			.on( "mouseup", function() { $(this).get(0).select(); } )
			.on( "input", handleRecipeChange );
		makeCurrentRecipe( myid );
	}

	myModule = {
		uuid: uuid,
		initPlugin: initPlugin,
		onBeforeCpanelClose: onBeforeCpanelClose,
		configurePlugin: configurePlugin,
		controlPanel: controlPanel,
		doRecipe: function() { try { doRecipe( api.getCpanelDeviceId() ); } catch(ex) { console.log(ex); alert(ex); } }
	};
	return myModule;
})(api, jQuery);
