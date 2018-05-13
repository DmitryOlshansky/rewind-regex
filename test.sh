#!/bin/bash
DC=${DC:-dmd}
dub test --compiler=$DC && cd tests && dub test --compiler=$DC
