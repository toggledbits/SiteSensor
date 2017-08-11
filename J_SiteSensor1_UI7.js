var SiteSensor = (function(api) {

    // unique identifier for this plugin...
    var uuid = '32f7fe60-79f5-11e7-969f-74d4351650de';

    var serviceId = "urn:toggledbits-com:serviceId:SiteSensor1";

    var myModule = {};

    function updateResponseFields() {
        var rtype = jQuery('select#rtype').val();
        jQuery('select#trigger option[value="match"]').attr('disabled', rtype != "text");
        jQuery('select#trigger option[value="neg"]').attr('disabled', rtype != "text");
        jQuery('select#trigger option[value="expr"]').attr('disabled', rtype != "json");

        // If the currently selected trigger value is disabled, select the first enabled one.
        var ttype = jQuery('select#trigger').val();
        if ( ttype === undefined || ttype === null || jQuery('select#trigger option[value="' + ttype + '"]').attr('disabled') ) {
            ttype = jQuery('select#trigger option:enabled').first().val();
            jQuery('select#trigger').val(ttype); // causes loop/recursion?
        }

        jQuery('input#pattern').attr('disabled', ttype != "match" && ttype != "neg");
        jQuery('input#tripexpression').attr('disabled', ttype != "expr");

        jQuery('div.tb-textcontrols').css('display', rtype == "text" ? "block" : "none");
        jQuery('div.tb-jsoncontrols').css('display', rtype == "json" ? "block" : "none");
    }

    function onBeforeCpanelClose(args) {
        // console.log('handler for before cpanel close');
    }

    function initPlugin() {
        api.registerEventHandler('on_ui_cpanel_before_close', myModule, 'onBeforeCpanelClose');
    }

    function configurePlugin()
    {
        try {
            initPlugin();

            var myDevice = api.getCpanelDeviceId();
            
            var i, j, roomObj, roomid, html = "";

            html += "<style>";
            html += ".tb-cgroup { padding: 0px 32px 0px 0px }"
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
            html += "<h2>Value Expressions</h2>";
            html += "<p>Use these expressions to draw values from the response JSON data and store them in state variables. You can use these values as triggers for scenes and Lua scripts.</p>";
            html += "<ol>";
            for (var ix=1; ix<=8; ix += 1) {
                html += '<li><input class="jsonexpr" id="expr' + ix + '" size="64" type="text"></li>';
            }
            html += "</ol>";

            html += '<p>The JSON data is encapsulated within a "response" key, so if your JSON data looks like the example below, the value <i>errCode</i> would be accessed by the expression <tt>response.errCode</tt>, while the value <i>name</i> would be accessed using <tt>response.type.name</tt>. Refer to the <a href="#">documentation</a> for more details.</p>';
            html += "<code>{\n    \"errCode\": 0,\n    \"type\": {\n        \"name\": \"Normal\",\n        \"class\": \"apiobject\"\n    }\n}</code>";

            html += "</div>"; // tb-jsoncontrols

            html += "<br/><hr>";

            // Push generated HTML to page
            api.setCpanelContent(html);

            // Restore values
            var s;
            s = api.getDeviceState(myDevice, serviceId, "RequestURL");
            jQuery("#requestURL").val(s ? s : "").change( function( obj ) {
                var newUrl = jQuery(this).val();
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
                newText = newText.replace(/\s+$/, ""); /* trim */
                newText = newText.replace(/([|%]|[^[:print:]])/g, function( m ) { return "%" + m.charCodeAt(0).toString(16); } ); /* escape our separator and non-printable */
                newText = newText.replace(/\s*(\r|\n|\r\n)/g, "|"); /* Convert newlines to our list breaks */
                api.setDeviceStatePersistent(myDevice, serviceId, "Headers", newText, 0);
            });

            s = parseInt(api.getDeviceState(myDevice, serviceId, "Interval"));
            if (isNaN(s))
                s = 1800;
            jQuery("input#interval").val(s).change( function( obj ) {
                var newInterval = jQuery(this).val();
                if (newInterval.match(/^[0-9]+$/) && newInterval >= 60)
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
                var newVal = jQuery(this).val();
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
            if (s) jQuery("input#pattern").val(s).change( function( obj ) {
                var newPat = jQuery(this).val();
                api.setDeviceStatePersistent(myDevice, serviceId, "Pattern", newPat, 0);
            });

            s = api.getDeviceState(myDevice, serviceId, "TripExpression");
            if (s) jQuery("input#tripexpression").val(s);
            jQuery("input#tripexpression").change( function( obj ) {
                var newExpr = jQuery(this).val();
                api.setDeviceStatePersistent(myDevice, serviceId, "TripExpression", newExpr, 0);
            });

            $('input.jsonexpr').each( function( obj ) {
                var ix = $(this).attr('id').substr(4);
                var s = api.getDeviceState(myDevice, serviceId, "Expr" + ix);
                if (s) $(this).val(s);
            });
            $('input.jsonexpr').change( function( obj ) {
                var newExpr = $(this).val();
                var ix = $(this).attr('id').substr(4);
                api.setDeviceStatePersistent(myDevice, serviceId, "Expr" + ix, newExpr, 0);
            });

            updateResponseFields();
        }
        catch (e)
        {
            Utils.logError('Error in SiteSensor.configurePlugin(): ' + e);
        }
    }

    myModule = {
        uuid: uuid,
        initPlugin: initPlugin,
        onBeforeCpanelClose: onBeforeCpanelClose,
        configurePlugin: configurePlugin
    };
    return myModule;
})(api);
