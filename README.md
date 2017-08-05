# SiteSensor #

## Introduction ##

SiteSensor is a plugin for Vera home automation system controllers that periodically makes requests of a remote  
server. Based on the response, it sets its "tripped" state (acting as a SecuritySensor device), and can also store
parsed values from JSON data. This makes it possible to use a remote RESTful API without writing a plugin.

This has many uses. A trivial use may be to periodically make requests of a remote web site simply to determine 
if your home internet connection is operating properly. An only slightly-less trivial use would be to probe a
remote site to determine that *it* is operating correctly (a poor man's up/down monitor). More complex, but
perhaps still fun, is that you can have SiteSensor query the Twitter API and trigger a scene in your home to
flash a light when someone mentions you in a tweet that contains the hashtag *#happyhour*.

Currently, only HTTP/HTTPS GET queries are supported, but future plans include support for additional HTTP methods
(POST, PUT, etc.), and direct TCP socket connections.

SiteSensor is written and supported by Patrick Rigney, aka rigpapa on the [Vera forums](http://http://forum.micasaverde.com/). 
For more information, see <http://www.toggledbits.com/>.

## Installation ##

The plugin is currently in beta test, so it cannot be installed from the Vera plugin store.

To install the plugin, download a release ZIP package from this site, and use the "Apps > Develop Apps > Luup Files"
page in the Vera console to upload the plugin files individually (not the ZIP file itself). 
Then create a device (Apps > Develop Apps > Create Device) with the following attributes (copy/paste recommended):

* Device Type: `urn:schemas-toggledbits-com:device:SiteSensor:1`
* Description: `SiteSensor`
* Upnp Device Filename: `D_SiteSensor1.xml`
* Upnp Implementation Filename: `I_SiteSensor1.xml`

Note that even though only two files are named above, you must still upload all of the files in the ZIP package.

## Simple Configuration ##

Configuration of SiteSensor is through the Device Settings page on the Vera Dashboard.

### RequestURL ###

This is the URL to be queried. It must be HTTP or HTTPS. Only the GET method is currently supported, and you cannot
add headers (e.g. Bearer, for authentication) currently, but this is planned.

### Request Interval ###

The request interval is the number of seconds between requests to the configured URL. This must be an integer > 60.
The default is 1800 (30 minutes).

### Query Only When Armed ###

This checkbox, which is on by default, causes SiteSensor to only query the configured URL when it is in "armed" state.
When disarmed, SiteSensor will not make queries.

### Request Timeout ###

This is the amount of time (in seconds) with which the server must respond before it is considered unreachable.
Any integer > 0 can be entered, but be conscious of the fact that performance of the Internet, your network, and the
server being queried, can case spurious "failure" notices for very small values. Giving your remote server at least
10 seconds to respond is recommended.

### Response Type ###

Currently, SiteSensor can handle responses in two ways: as text, or as JSON data. The default is text. For information
on handling JSON responses, see the Advanced Configuration section.

### Trigger Type ###

SiteSensor operates as a SecuritySensor class device, so it has a "triggered" property, just as an alarm sensor in that class, 
like a motion detector, would.
Setting the trigger type determines how SiteSensor will control its "triggered" status.

The default trigger type is "URL unreachable or server responds with error." In this case, any problem receiving a valid
response from the server causes the SiteSensor device to enter triggered state. A successful query restores it from triggered
state. This trigger type is available with any response type.

There are two pattern match states, one for positive match, and one for negative match. These cause SiteSensor to look for
a string in the returned result text, and are therefore only available when the response type is text. For a positive match, 
the SiteSensor device will enter triggered state if the pattern string is found in the response text. For a negative match, the
device is only triggered if the pattern is *not* found in the response text.

Additional trigger types applies to JSON responses, and are documented under Advanced Configuration below.

## Advanced Configuration ##

### JSON Responses ###

SiteSensor can retrieve and parse JSON from the remote server. You can then use expressions to fetch values from the
decoded data and store those in SiteSensor state variables (which are visible to Lua, PLEG, etc). Evaluation of an
expression using the JSON data can also be used to set the SiteSensor device's *tripped* state.

To configure SiteSensor for JSON response, set the "Response Type" field to *JSON data*.

#### Trip Conditions ####

By default, SiteSensor's triggering mechanism follows the success of the query. That is, if the query fails, SiteSensor
enters triggered state. For JSON queries, the server must respond with a complete, non-error response, and the response
must be fully parsed as JSON without error, for the query to be deemed successful. Either failure of the server to provide
a response, or failure of the response to parse correctly, will cause the device to be triggered.

When the response type is JSON data, the pattern-matching options for trigger type are disabled,
and an additional option is presented: "When the result of an expression is true". This allows the entry of an expression
which is evaluated against the response data, and if the expression is (logically) true, the device enters triggered state.
The following conditions apply:

* Boolean *true* and *false* mean what they normally mean;
* For numeric results, integer zero (0) is considered *false* and anything else is *true*;
* For string results, the empty string is *false* and any non-empty (length > 0) string is *true*;
* For anything else, Lua *nil* is *false* and anything else is *true*.

#### Expressions ####

SiteSensor will evaluate up to 8 expressions and store the results. The results are stored in variables named `Value1`,
`Value2`, ..., `Value8`.  These variables send events when their value changes, so you can use them as triggers for 
scenes and Lua.

Expressions work pretty much as expected, with standard operator precedence, grouping (and nesting) with parentheses, 
and a small library of helpful functions. The syntax is similar to that of Lua.

Expressions use dot notation to navigate the tree of values in the decoded JSON response. Let's consider this JSON response. We'll use it for all of the examples in this section:

```
{  
   "status":"OK",
   "timestamp":"1484492903",
   "temperature":{  
      "degrees":"72",
      "unit":"fahrenheit"
   },
   "listitems":[  
      "1",
      "32",
      "1882",
      "128331"
   ],
   "alerts":[  
      {  
         "id":"NOACT",
         "text":"No account available",
         "code":"1033"
      },
      {  
         "id":"177",
         "text":"Door prop alarm",
         "code":"4100",
         "since":"1484492903",
         "zone":"5"
      },
      {  
         "id":"177",
         "text":"Door prop alarm",
         "code":"4100",
         "since":"1484493071",
         "zone":"13"
      },
      {  
         "id":"200",
         "text":"Invalid card at reader",
         "code":"7000",
         "since":"1484492903",
         "zone":"1",
         "card":"27492"
      }
   ]
}
```

SiteSensor places the returned JSON data underneath a key called "response". An additional key, "status", contains information
about the query itself and is explained later.

The simplest elements in this data to access are those at the "root" of the tree, such as "status". This would be returned by simply
using the expression `response.status`. Elements nested within other elements are accessed by navigating through the parent, so accessing
the current temperature in this example would be `response.temperature.degrees`.

You can do math on a referenced value in the usual way. For example, to convert the current temperature to celsius, we would
use the expression `(response.temperature.degrees-32)*5/9`. Note that we've also used parentheses to control precedence here. Multiplication
and division both have higher operator precedence than subtraction, so without the parentheses, this expression would first evaluate
32*5/9 and then subtract that result from `response.temperature.degrees`, which would be incorrect. Nesting of parentheses is permitted, of course.

Operators (in order of precedence from highest to lowest): *, /, %; +, -; <, <=, >, >= (magnitude comparison); ==, != (equality and inequality); & (binary AND); ^ (binary NOT); | (binary OR).

The expression evaluator has a modest library of functions as well:

Math functions: abs(n), sin(n), cos(n), tan(n), sgn(n), floor(n), ceil(n), round(n), exp(n), pow(n, m), sqrt(n), min(n,m), max(n,m)

String functions: len(s), find(s, p [,i]), sub(s, n [,l]), upper(s), lower(s), tonumber(s [,n]), tostring(v)

Other functions: time(), strftime( fmt [,t] ), choose( n, d, v1, v2, ...), select( obj, key, val )

Array elements can be accessed using square brackets and the desired element number. The value of the third element in `response.listitems` 
in our example would therefore be returned using the expression `response.listitems[3]`. Array subscripts can also be strings, and in this 
usage, `response.temperature.degrees` and `response['temperature']['degrees']` are synonymous (the dot-notation is a shortcut).

The "alerts" array is an interesting case--it's an array of objects. Let's say we needed to find the array element with id equal to 200. We can see it's
the fourth element, so we could refer to it by using `response.alerts[4]`. But, what if one or more of the other alerts disappears? The correct way
to find the element in this array is to use the select() function: select(response.alerts, "id", 200). The result of this function is the object
having a key named "id" equal to the value 200, regardless of its position within the alerts array.

The choose() function takes two or more arguments (usually more than two). The first argument is an index, and the second a default value. The function returns
its (index+2)th argument, if it exists, or the default value otherwise. For example, choose(3, "no", "first", "second", "third", "fourth") returns "third",
while choose(9, "no", ...same list...) returns "no". This allows you to quickly index numeric values to strings.

#### Query Status ####

For JSON responses, in addition to the *response* container for the data returned by the server, SiteSensor provides a
*state* container with the following fields:

* *valid* -- 0 or 1 (false or true) to indicate if the *response* container contains valid data;
* *timestamp* -- the Unix timestamp of the server response;
* *httpStatus* -- the HTTP status returned by the server (200=OK, etc.);
* *jsonStatus* -- the result of the JSON decoding of any data returned by the server ("OK" or an error message).

A simple trip expression, for example, might be `status.valid != 1`, which would case the device to enter tripped
state any time the server response isn't valid (this is effectively the same as choosing the URL/response error
trigger--it's just an example).

## Troubleshooting ##

## FAQ ##

<dl>
    <dt>How long is a piece of string?</dt>
    <dd>Its entire length from one end to the other, measured in either direction.</dd>
</dl>        

## Reporting Bugs/Enhancement Requests ##

Bug reports and enhancement requests are welcome! Please use the "Issues" link for the repository to open a new bug report or make an enhancement request.

## License ##

SiteSensor is offered under GPL (the GNU Public License) 3.0. See the LICENSE file for details.
