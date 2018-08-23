//# sourceURL=J_SiteSensorProbe1_ALTUI.js
/**
 * J_SiteSensorProbe1_ALTUI.js
 * Copyright 2018 Patrick H. Rigney, All Rights Reserved. 
 * AltUI special UI implementation for SiteSensor devices.
 */
/* globals MultiBox */

"use strict";

var SiteSensor_ALTUI = ( function( window, undefined ) {

        function _draw( device ) {
                var html ="";
                var message = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:SiteSensor1", "Message");
                html += '<div style="font-size: 0.8em;">';
                html += message;
                html += "</div>";
                return html;
        }
        
    return {
        DeviceDraw: _draw,
    };
})( window );
