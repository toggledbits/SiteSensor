//# sourceURL=J_SiteSensor1_ALTUI.js
/**
 * J_SiteSensor1_ALTUI.js
 * Copyright 2018 Patrick H. Rigney, All Rights Reserved.
 * AltUI special UI implementation for SiteSensor devices.
 */
/* globals MultiBox,ALTUI_PluginDisplays,_T */

"use strict";

var SiteSensor_ALTUI = ( function( window, undefined ) {

		function _draw( device ) {
				var html ="";
				var message = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:SiteSensor1", "Message");
				var st = MultiBox.getStatus( device, "urn:micasaverde-com:serviceId:SecuritySensor1", "Armed");
				html += '<div style="font-size: 0.8em;">';
				html += message;
				html += "</div>";
				html += ALTUI_PluginDisplays.createOnOffButton( st, "toggledbits-sitesensor-" + device.altuiid, _T("Disarmed,Armed"), "pull-right");
				html += "<script type='text/javascript'>";
				html += "$('div#toggledbits-sitesensor-{0}').on('click', function() { SiteSensor_ALTUI.toggleArmed('{0}','div#toggledbits-sitesensor-{0}'); } );".format(device.altuiid);
				html += "</script>";
				html += '<div>';
				html += MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:SiteSensor1", "Value1" );
				html += '</div>';
				return html;
		}

		function _favorite( device ) {
			var html = "";
			var val = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:SiteSensor1", "Value1" ) || "";
			// html += '<img src="https://www.toggledbits.com/assets/sitesensor/sitesensor-default.png" width="60" height="60"><br/>';
			html += "<span class='altui-favorites-mediumtext'>" + val + '</span>';
			return html;
		}

	return {
		/* convenience exports */
		toggleArmed: function (altuiid, htmlid) {
				ALTUI_PluginDisplays.toggleButton(altuiid, htmlid, 'urn:micasaverde-com:serviceId:SecuritySensor1', 'Armed', function(id,newval) {
						MultiBox.runActionByAltuiID( altuiid, 'urn:micasaverde-com:serviceId:SecuritySensor1', 'SetArmed', {newArmedValue:newval} );
				});
		},
		/* "real" exports */
		DeviceDraw: _draw,
		Favorite: _favorite
	};
})( window );
