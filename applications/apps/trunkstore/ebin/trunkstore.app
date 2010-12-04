{application,trunkstore,
             [{description,"Trunk Store Backend - Authentication and Routing"},
              {vsn,"0.3.1"},
              {registered,[]},
              {applications,[kernel,stdlib,whistle_amqp,whistle_couch]},
              {mod,{trunkstore_app,[]}},
              {env,[]},
              {modules,[trunkstore,trunkstore_app,trunkstore_deps,
                        trunkstore_sup,ts_auth,ts_call_handler,ts_carrier,
                        ts_cdr,ts_credit,ts_e911,ts_responder,ts_route,ts_t38,
                        ts_util]}]}.