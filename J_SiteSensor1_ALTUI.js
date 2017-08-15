//# sourceURL=J_SiteSensor1_ALTUI.js
"use strict";

var SiteSensor_ALTUI = ( function( window, undefined ) {

        function _draw( device ) {
                var html ="";
                var message = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:SiteSensor1", "Message");
                var st = MultiBox.getStatus( device, "urn:micasaverde-com:serviceId:SecuritySensor1", "Armed");
                html += '<div class="pull-left">';
                html += message;
                html += "</div>";
                html += ALTUI_PluginDisplays.createOnOffButton( st, "toggledbits-sitesensor-" + device.altuiid, _T("Disarmed,Armed"), "pull-right");
                html += "<script type='text/javascript'>";
                html += "$('div#toggledbits-sitesensor-{0}').on('click', function() { SiteSensor_ALTUI.toggleArmed('{0}','div#toggledbits-sitesensor-{0}'); } );".format(device.altuiid);
                html += "</script>";
                return html;
        }
    return {
        DeviceDraw: _draw,
        toggleArmed: function (altuiid, htmlid) {
                ALTUI_PluginDisplays.toggleButton(altuiid, htmlid, 'urn:micasaverde-com:serviceId:SecuritySensor1', 'Armed', function(id,newval) {
                        MultiBox.runActionByAltuiID( altuiid, 'urn:micasaverde-com:serviceId:SecuritySensor1', 'SetArmed', {newArmedValue:newval} );
                });
        },
    };
})( window );
