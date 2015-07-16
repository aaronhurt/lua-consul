### Introduction

   This is a lua module to interact with consul (https://consul.io) HTTP API.
It's already quite usable, but it is under rapid development, so at the moment
it covers only a fraction of consul API.

### Dependencies

   We need luasocket, luasec and lua-cjson, which are, luckily, mentioned in the rockspec

### Variables and functions
#### Variables

* **consul.url** - this one is built upon initialisation, based on the following rules: 
                    
If environment variable **CONSUL_URL** is present, **consul.url** will be set to its value, and it also
will be parsed to get **consul.scheme** and **consul.port**.
                    
If there is no **CONSUL_URL** env var, **consul.url** will be built thusly:
```
consul.url = consul.scheme .. '://consul.service.' .. consul.domain .. ':' .. consul.port
```

* **consul.domain** - built upon init, based on the envrionment var **CONSUL_DOMAIN** or defaults to 'consul' 
* **consul.port** - built upon init, based on the environment var **CONSUL_PORT** or defaults to '8500'. 
* **consul.scheme** - built upon init, either defaults to 'http' or deducted from **CONSUL_URL** env var.
Based upon its' value we will require either socker.http or ssl.https.

* **consul.body** - response body after performing an API request. Although consul provides responses in json,
in lua terms it's just a string. We use cjson.decode to convert json string into a lua table, 
and cjson.encode to convert a lua table into a string with proper json. 

* **consul.status** - response status after the request (number)
* **consul.headers** - response headers after the request

#### Functions

* **consul:get( key, [raw] )** - *key* should be the key prefix, if *raw* is present and is true, 
the function will ask for the raw key value. Returns the obtained response body and also puts it into **consul.body**

* **consul:get_keys( prefix )** 
* **consul:put( key, value )**  
* **consul:delete( key )**  
* **consul:health_service( service, [tag] )** 
* **consul:health_state( [state] )**                                                                                                                     
