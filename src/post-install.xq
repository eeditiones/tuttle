xquery version "3.1";

declare namespace sm="http://exist-db.org/xquery/securitymanager";

(: The following external variables are set by the repo:deploy function :)

(: file path pointing to the exist installation directory :)
declare variable $home external;
(: path to the directory containing the unpacked .xar package :)
declare variable $dir external;
(: the target collection into which the app is deployed :)
declare variable $target external;

sm:chmod(xs:anyURI($target||"/modules/api.xq"), "rwxr-sr-x"),
sm:chmod(xs:anyURI($target||"/data/tuttle.xml"), "rw-r-----")
