# CHANGELOG #

## Version 1.15 (development)

* Fix: Make sure dkjson decodes "null" to LuaXP's *null* value rather than Lua `nil`.
* Fix: Some versions of Luasec require the SSL protocol to be set, they don't default, so use "all" for LuaSec > 0.5 (7.31 firmware except Edge), and "tlsv1" for 0.5.
* Enhancement: Force default room for child device to same room as parent at initialization (can be moved after).
* Enhancement: When a new child is created, copy the current value of the expression to the newly-initialized child.
* Enhancement: Load and create recipes. A recipe is a saved/packaged configuration that can be deployed easily.
* Enhancement: Add `SetEnabled` action (parameter `newEnabledValue`) to set enable/disable state of a SiteSensor. When disabled, queries are not run. This provides an alternate mechanism to the arm/disarm control to control queries without Luup notifications that accompany security sensor arming state. Requested by whyfseeguy.

## Version 1.14 (released)

* Fix a bug in handling of very long responses that causes them to sometimes be stored when they should be skipped. Not generally a problem for anyone, but the idea is to avoid over-bloating user_data, and if that doesn't work right consistently, goal not achieved.

## Version 1.13 (released)

* Prevent really large responses from being stored for history/re-evaluation. This results in potentially excessive size of state variables, and thus Luup's `user_data` structure.
* Update to latest version of LuaXP.

## Version 1.12 (released)

* Implement `finddevice()` and `getstate()` extensions functions to LuaXP, identical to their Reactor counterparts.
* Allow use of `curl` as a conduit for JSON requests by setting `UseCurl`. This works around some limitations in LuaSec that we can't resolve easily, or at all.
* Capture raw response to JSON request if it's not exorbitantly large.
* Handle no-data responses better--be more definitive in showing the user that no data was returned (otherwise, it's misleading).
* When failing parent device, also fail child devices.

## Version 1.11 (released)

* Fix timezone offset problem in request parameter substitution;
* Add `DeviceErrorOnFailure` state variable to control behavior when queries fail (1=default, fail state also sets Luup device failure status, 0=do not set Luup device status).

## Version 1.10 (released)

* Support for more than 8 (default) expressions in JSON requests. This is currently done by setting the NumExp state variable.
* Support virtual sensors as target value containers for expression results on Vera Luup. This feature is not available on openLuup.
* Add SSL control state variables SSLVerify, SSLProtocol, SSLOptions, and CAFile, which pass their values through to the underlying library.
* Improved error feedback to user on match queries, particularly when connection errors occur.
* Implement `DoRequest` action to force immediate request and update.

## Version 1.9 (released) ##

* Make category and subcategory assignment more definitive.
* References to non-existent subkeys now do not issue runtime error, but return null. This allows functions like `if()` to check for and gently handle missing data (e.g. OpenWeatherMap.org does not always return wind data in its API response). This is actually a change made entirely to luaxp; the version of luaxp used by SiteSensor has been updated;
* Support for `MessageExpr` state variable that, when set and non-empty, pushes the value of the expression to the device message on the dashboard card. In other words, this change lets you control the message that appears with the device on the dashboard;
* Add scene/notification triggers for numeric comparisons of the 8 user-definable expressions;
* Let Vera manage `ArmedTripped` entirely. This gives SiteSensor Vera's semantics for `ArmedTripped` (i.e. `ArmedTripped` only changes state at edges of `Tripped` when `Armed`=1; it is not reset to 0 when `Armed` is changed from 1 to 0 while `Tripped`=1, nor set to 1 when `Armed` is changed from 0 to 1 while `Tripped`=1);
* Remove reference to makersupport.com for donations (they are currently defunct, unable to process payments), and direct would-be donors to a page on my web site.

## Version 1.8 (released) ##
Released for openLuup only

* Fix namespace in XML header to comply with requirements of akbooer's new XML parser. This change affects openLuup only.

## Version 1.7 (skipped) ##

## Version 1.6 (released) ##

* Support refresh of previous query results intermittently, to allow re-evaluation of time-based expressions with forcing a refetch from the remote API.

## Version 1.5 (hotfix; released) ##

* This version addresses an issue with certain dot-notation subreferences failing.

## Version 1.4 (released) ##

* Adds scene/notification triggers for boolean state of the 8 user-definable expressions;
* Adds UI on the control panel to enable request logging;
* Adds control panel display of log messages (when enable) and status indicators;
* Changes the category and subcategory to appear like a door sensor (security sensor);
* Adds support for ImperiHome ISS API;
* Uses the latest version of luaxp for better expression evaluation, and in particular, adds better support for date/time handling; also fixes many evaluator bugs;
* In support of time-relative response data and expressions, add the option to periodically re-evaluate expressions without refetching data. This avoids spamming remote APIs for time-based data that changes infrequently in order to force expression evaluation against current date/time.
* Set a default value for ModeSetting state variable in an attempt to avoid Vera's default changing the armed/disarmed state automatically.

## Version 1.3 (released) ##

* Minor bug fixes only.

## Version 1.2 (released) ##

* Support for ALTUI and openLuup.

## Version 1.1 (released) ##

* Initial public release.
