# SiteSensor #

## Introduction ##

SiteSensor is a plugin for Vera home automation controllers that periodically makes requests of a remote
server. Based on the response, it sets its "tripped" state (acting as a SecuritySensor device), and can also store
parsed values from JSON data. This makes it possible to use a remote RESTful API without writing a plugin.

This has many uses. A trivial use may be to periodically make requests of a remote web site simply to determine
if your home internet connection is operating properly. An only slightly-less trivial use would be to probe a
remote site to determine that *it* is operating correctly (a poor man's up/down monitor). More complex, but
perhaps still fun, is that you can have SiteSensor query the Twitter API and trigger a scene in your home to
flash a light when someone mentions you in a tweet that contains the hashtag *#happyhour*.

Currently, only HTTP/HTTPS GET queries are supported, but future plans include support for additional HTTP methods
(POST, PUT, etc.), and direct TCP socket connections.

SiteSensor has been tested on openLuup with AltUI.

SiteSensor is written and supported by Patrick Rigney, aka rigpapa on the [Vera forums](http://http://forum.micasaverde.com/).

For more information, see <http://www.toggledbits.com/sitesensor/>.

## Reporting Bugs/Enhancement Requests ##

Bug reports and enhancement requests are welcome! Please use the "Issues" link for the repository to open a new bug report or make an enhancement request.

## License ##

SiteSensor is offered under GPL (the GNU Public License) 3.0. See the LICENSE file for details.
