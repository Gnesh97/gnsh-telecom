# TP-06 progress: urban and town coverage balancing

## Runtime evidence received

- Downtown heatmap: tower placement is broadly coherent; service transitions
  from green through yellow/orange toward the edge with isolated red cells.
- Sandy Shores heatmap: the town center is green and the outskirts degrade
  toward orange/red rather than becoming uniformly strong.
- Paleto heatmap: the settlement is green with degradation toward the remote
  edge and Chiliad transition.
- Coverage expectation summary: `pass=20 fail=0 pending=0`.

The evidence supports keeping the current tower locations and radii. The
observed issue is the shape of the signal curve inside a radius, so TP-06
introduces a small, configurable falloff adjustment instead of moving or
adding towers.

## Tuning change

`Config.Signal.DistanceFalloffExponent` is set to `1.25`.

- `1.0` is the previous linear curve.
- Values above `1.0` preserve more signal in the middle of a radius.
- The signal still reaches zero at the exact radius boundary.
- Intentional weak anchors remain protected by the existing expectation tests.

## Acceptance status

The code change is ready for FiveM retest after `restart gnsh-telecom`.
TP-06 remains in progress until downtown, Sandy and Paleto heatmaps plus the
first highway drive route are checked with the new curve.
