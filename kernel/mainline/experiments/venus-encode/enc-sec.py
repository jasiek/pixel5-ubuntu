# SPDX-License-Identifier: GPL-2.0-only
# The working encoder experiment (Tests 235-248): enc-base.py (E1 unset) + sec.py.
# Run inside drivers/media/platform/qcom/venus with EXP set to this directory.
import os
d = os.environ['EXP']
exec(open(os.path.join(d, 'enc-base.py')).read())
exec(open(os.path.join(d, 'sec.py')).read())
