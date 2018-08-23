# CHANGELOG #

## Version 1.10 (develop branch) ##

* SiteSensor has been converted to the parent/child plugin model, which is vastly more resource efficient in the constrained Vera execution environment. Existing SiteSensor instances will be converted to child devices, and the plugin attempts to find scene trigger references to the old devices and remap them to the new child devices. However, sensor references in notifications, Lua or PLEG are not converted automatically, and so must be located and changed by hand. Sorry guys, but it's a one time change for a big benefit, and I deemed this a necessary evil, and it should only inconvenience a minority of users.

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
