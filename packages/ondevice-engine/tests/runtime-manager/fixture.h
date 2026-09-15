// TEST-ONLY process; never include this backend in an application target.
#include "mm_runtime.h"
mm_status mm_install_graal_backend(void);
void fixture_mode(int mode);
void fixture_busy_closes(int count);
int fixture_close_calls(void);
