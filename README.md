SiteSensor
=============

## Introduction ##

SiteSensor is a plugin for the MiOS home automation operating system used on MiCasaVerde Vera gateway/controllers.
It periodically makes requests of a remote HTTP server and scans the response body for a pattern string. When matched,
the virtual sensor shows tripped. SiteSensor can store all or part of the string matched as well, making it possible
to use as a remote data retrieval mechanism (i.e. it can make a request of a RESTful or similar API and store the
result).
Currently, only HTTP is supported, but future plans include support for any type of
TCP socket connection, and send/expect strings.

## Installation ##

## Simple Configuration ##

### Parameter ###

Parameter use/meaning/restrictions.

### Parameter ###

Parameter use/meaning/restrictions.

## Advanced Configuration ##

### JSON Responses ###

SiteSensor can retrieve and parse JSON from the remote server. You can then use expressions to fetch values from the
decoded data and store those in SiteSensor state variables (which are visible to Lua, PLEG, etc). Evaluation of an
expression using the decoded data can also be used to set the SiteSensor device's //tripped// state.

SiteSensor will evaluate up to 8 expressions and store the results. The results are stored in variables named `Value1`,
`Value2`, ..., `Value8`. 

The special "Trip Condition" expression, if provided, will set SiteSensor's tripped state to the result of the expression
evaluation. For these purposes, if the expression result is a *numeric* value, 0 evaluates to *false* and anything else is
*true*; for *string* results, the empty string is *false* and any non-empty string is *true*; otherwise, nil or empty means
*false* and anything else means *true*. If the Trip Condition is not provided, the device's tripped state follows the 
success of the last query (tripped on error, not tripped if valid response). 

#### Expressions ####

Expressions work pretty much as expected, with standard operator precedence, grouping (and nesting) with parentheses, 
and a small library of helpful functions. 

Expressions use dot notation to navigate the tree of values in the decoded JSON response. Let's consider this JSON response. We'll use it for all of the examples in this section:

```
{  
   "status":"OK",
   "timestamp":"1484492903",
   "temperature":{  
      "value":"72",
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
         "since":"1484492903",
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

The simplest elements in this data to access are those at the "root" of the tree, such as "status". This would be returned by simply
using the expression `status`. Elements nested within other elements are accessed by navigating through the parent, so accessing
the current temperature in this example would be `temperature.value`.

You can do math on a referenced value in the usual way. For example, to convert the current temperature to celsius, we would
use the expression `(temperature.value-32)*5/9`. Note that we've also used parentheses to control precedence here. Multiplication
and division both have higher operator precedence than subtraction, so without the parentheses, this expression would first evaluate
32*5/9 and then subtract that result from `temperature.value`, which would be incorrect. Nesting of parentheses is permitted, of course.

Operators (in order of precedence from highest to lowest): *, /, %; +, -; <, <=, >, >= (magnitude comparison); ==, != (equality and inequality); & (binary AND); ^ (binary NOT); | (binary OR).

The expression evaluator has a modest library of functions as well:

Math functions: abs(n), sin(n), cos(n), tan(n), sgn(n), floor(n), ceil(n), round(n), exp(n), pow(n, m), sqrt(n), min(n,m), max(n,m)

String functions: len(s), find(s,t,p), sub(s,p,l), cat(s, ...), upper(s), lower(s), tonumber(s,n), tobool(s), format(s, ...)

Other functions: time(), tostring(v)

Array elements can be accessed using square brackets and the desired element number. The value of the third element in `listitems` 
in our example would therefore be returned using the expression `listitems[3]`. Array subscripts can also be strings.

Now, the "alerts" array is an interesting case. Let's say we needed to find the array element with id=200. We can see it's
the fourth element, so we could refer to it by using `alerts[4]`. But, what if one or more of the other alerts disappears? The correct way
to find the element in this array is to use special array subscript notation. This example returns the "text" element of the array object
having id=200: `alerts[id="200"].text`

FUTURE: You can also nest JSON data in an expression. For example, `{ "firstname": "toggled", "lastname": "bits" }` would evaluate to a JSON
object with two elements, "firstname" and "lastname". The following example uses an object created on-the-fly to use as a map for converting
the temperature unit name in our example to a one-letter display indicator. The result value of this expression is "F" if the unit is fahrenheit,
and "C" if the unit is celsius: `{"fahrenheit":"F", "Celsius":"C"}[temperature.unit]`. Numeric arrays can also be created and used this way: 
`[100,200,300,400][3]` returns 300.

## Troubleshooting ##

## FAQ ##

<dl>
    <dt>How long is a piece of string?</dt>
    <dd>It's entire length from one end to the other, measured in either direction.</dd>
</dl>        

## Reporting Bugs/Enhancement Requests ##

Bug reports and enhancement requests are welcome! Please use the "Issues" link for the repository to open a new bug report or make an enhancement request.

## License ##

SiteSensor is offered under GPL (the GNU Public License). See the LICENSE file for details.
