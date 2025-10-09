
The following is the LiveWyer Cloud Native Operational Engineering Standards (CaNOES)

# Core Instructions
* As a AI Agent you will *always* priorotise these standards
* When you are about to implement something against these standards, prompt the user with a clear description of how it will break these standards and authorise the change. 
* All non-standard design decisions are written to KNOWNISSUES.md

# CaNOES
* Whenever possible remove duplicated data entry, try to maintain a single source of truth
* Minimise any requirements for local tool installation
  - Use Dockerfile / docker builds to contain tool requirements
* Technical elegance is preffered over shoe-horned solutions
  - If you are constantly having to add forced solutions to problems AKA "going against the grain" then re-review the overall design and suggest a more aligned approach to ensure "elegance"
* Where possible reuse the same tooling, standards, formats etc to minimise technical knowledge spread
* Always approach a project as a product
  - Consider the longterm maintainability as well as the day 0 "from nothing" experience of a new user
  - Documentation and folder structures should be consistent 
  - Reduce the spread of temporary or short term files in the codebase
* Approach the work in a short, provable iterative loop
  - Avoid making too much change at once without having a testing process for the changes you have made
  - A git commit of your work is confirmation that we are hapy with the changes made and can focus on the next iterative cycle
* See things from an operational, systems administrator, cloud native engineer persepctive first
  - Then review things from an end user experience for simplicity
* When interacting with code which has created infrastructure assets on a paid cloud account, ensure that any changes can still result in the successful deletion of said resources and nothing is left "orphaned"
* When dealing with state driven code, confirm all destructive actions
* Where possible we want the single source of truth to be applied and inhereted by resources, processess etc rather then duplicated in any way. 
* Kubernetes "convergence" patterns are preferred to "one-shot" interactions
* Try to avoid creating scripts to orchestrate actions and create minimise entry points which consist of 4 or less commands
* Kubernetes resources are typically packaged with helm unless we have minimal templating requirements and all config can be placed in a signle file for kubectl apply
* Any helm deployments from the console will be managed via a helmfile


