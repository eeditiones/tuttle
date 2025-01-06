xquery version "3.1";
(:~
    Default callbacks
    
    callbacks must have the signature
    function(map(*), map(*)) as item()*
 :)
module namespace cb="http://e-editiones.org/tuttle/callbacks";

(:~
 : example callback
 : It will just return the arguments the function is called with
 : for documentation and testing purposes
 :
 : the first argument is the collection configuration as a map
 : the second argument is a report of the changes that were applied
 : example changes

map {
    "del": [
        map { "path": "fileD", "success": true() }
    ],
    "new": [
        map { "path": "fileN1", "success": true() }
        map { "path": "fileN2", "success": true() }
        map { "path": "fileN3", "success": false(), "error": map{ "code": "err:XPTY0004", "description": "AAAAAAH!", "value": () } }
    ],
    "ignored": [
        map { "path": "fileD" }
    ]
}

: each array member in del, new and ignored is a 

record action-result(
 "path": xs:string,
 "success": xs:boolean,
 "error"?: xs:error()
)
:)
declare function cb:test ($collection-config as map(*), $changes as map(*)) {
    map{
        "callback": "cb:test",
        "arguments": map{
            "config": $collection-config, 
            "changes": $changes
        }
    }
};