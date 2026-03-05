# Chapter 30: Where To Carve Next

The dawn bell sounds twice in Ironhold: once for the miners, and once for the clerks who must decide which warnings were noise and which were prophecy. By first light the watch ledger is already warm from too many hands.

The Runewarden does not get to choose between theory and duty. The mountain asks for both. A bad proof is useless in a collapse. A fast patch without invariants is only a delayed collapse. So the final lesson is not a new operator. It is how to steer the language once the tutorial scaffold is gone.

By Chapter 29 we built a complete vertical slice: typed domain data, pure business logic, effectful shells, datastore swapping, actor supervision, protocol checks, web boundaries, sessions, and hardening. That stack is enough to build software that does real work.

The important point is not that every layer is perfect. The important point is that every layer is visible. In Cairn, shape is explicit. Stack effects are explicit. Side effects are explicit. Failure channels are explicit. You can read a function signature and know what power it has and what obligations it carries.

Assurance in Cairn is strongest when used as a loop, not as a ceremony. `TEST` protects known examples. `VERIFY` pressures broad input space and catches boundary mistakes that examples miss. `PROVE` settles bounded obligations where symbolic arithmetic applies. Effects constrain where IO and persistence are allowed to occur. None of these tools replace design, but together they make design honest.

This book also exposed the practical boundary. Solver-backed proof is excellent for local arithmetic and structural invariants. It is not the right tool for process scheduling, browser behavior, or distributed timing. For those domains, we relied on type discipline, explicit protocols, supervised runtime behavior, and operational tests. That split is healthy. It keeps proof where proof is crisp and keeps engineering where engineering belongs.

If you want one final runnable milestone before leaving the book, run the hardened capstone and exercise both happy and unhappy paths:

```bash
./cairn book/code/runewarden/chapters/ch29_safety_review_and_hardening/main.crn
curl -i http://127.0.0.1:8135/health
curl -i -c /tmp/ch30.cookies -X POST -d 'username=warden&password=ironhold' http://127.0.0.1:8135/login
curl -i -b /tmp/ch30.cookies -X POST -d 'kind=oops&magnitude=999' http://127.0.0.1:8135/add
```

You should see a healthy service, successful authentication, and a bounded `400 Bad Request` for malformed incident input. That is the shape of a trustworthy boundary: useful to good clients, boring to malicious ones.

From here, the roadmap naturally splits into three practical campaigns.

First, deepen data modeling where application code still leans on ad hoc maps. Records and richer product shapes reduce accidental key mismatches and make web and datastore code read closer to the domain. The language has already moved in that direction with tuples and generic ADTs; continuing that work pays immediate dividends.

Second, keep tightening effect boundaries around infrastructure integrations. The database path already moved from direct runtime calls to a backend boundary and then to Postgres. The same discipline should guide additional integrations: narrow host interop, explicit effect annotations, and test surfaces that can run locally and in CI without hidden machine state.

Third, continue the web story without turning Cairn into framework sprawl. The right next features are the ones that preserve language clarity while enabling real applications: request/response boundary polish, authentication/session lifecycle hardening, and composable helpers that remain thin over explicit primitives.

The mountain metaphor has done enough work; now the code must do the rest. The book is finished, but the project is not. A good next Cairn program should be chosen not by novelty, but by pressure: pick the one that forces one missing piece into the open, implement that piece cleanly, and fold it back into the language with tests and documentation.

When the next bell rings, you should be able to answer three questions quickly: what this program promises, where it can fail, and how we know it behaves. If Cairn keeps making those answers easier to obtain, it is on the right path.
