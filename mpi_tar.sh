#! /usr/bin/env mpibash

# Script to run multiple tar commands using MPIBash
#
# Usage:
#
# mpi_tar.sh <directory to be archived>
#
# This assumes that the directory to be cleaned is the top-level
# OpenFOAM case directory (i.e., where processor0, processor1,
# etc. are located)


# Set up MPI Bash env
enable -f mpibash.so mpi_init
mpi_init
mpi_comm_rank rank
mpi_comm_size nranks

# Get target directory and submit directory
target_dir="$(readlink --canonicalize $1)"
if [ $rank -eq 0 ]; then
  echo "Archiving directory: $target_dir"
fi

# Get number of time step directories
n_tsteps=`ls $target_dir/processor0 | wc -l`

# Figure out how to divide the time step directories amongst processors
count="$(( $n_tsteps/$nranks ))"
remainder="$(( $n_tsteps%$nranks ))"

if [ $rank -lt $remainder ]; then
  start=$(( $rank*($count+1) ))
  stop=$(( $start+$count ))
else
  start=$(( ($rank*$count)+$remainder ))
  stop=$(( $start+($count-1) ))
fi

# Store time step directories in an array
# This prevents having to do an `ls` in each loop iteration
cd $target_dir/processor0
shopt -s nullglob
TSTEPS=(*)

# Loop over processor directories
# Each bash process will create a tar file name timesteps_$rank.tar
# that contains a portion of the time step directories
for dir in $target_dir/processor*; do
  for ((i=start; i<=stop; ++i)); do
    # Create a file with the list of directories to be tarred
    # This lets us run one tar at the end of the loop
    echo ${TSTEPS[$i]} >> $dir/rank${rank}_filelist$$
  done
  tar -cf $dir/timesteps_$rank.tar -C $dir -T $dir/rank${rank}_filelist$$

  # Synchronize everyone before deleting files
  mpi_barrier

  # Loop over local list of timestep directories and delete files
  for ((i=start; i<=stop; ++i)); do
    find $dir/${TSTEPS[$i]} -type f -print0 | xargs -0 munlink
  done

  # Synchronize again and remove the timestep directories
  mpi_barrier
  for ((i=start; i<=stop; ++i)); do
    find $dir/${TSTEPS[$i]} -depth -type d -empty -delete
  done
  rm $dir/rank${rank}_filelist$$
done

# Repeat the process for the top-level files and directories
# Get number of files and directories
n_files=`ls $target_dir | wc -l`

# Figure out how to divide the files & directories amongst processors
top_count="$(( $n_files/$nranks ))"
top_remainder="$(( $n_files%$nranks ))"

if [ $rank -lt $top_remainder ]; then
  top_start=$(( $rank*($top_count+1) ))
  top_stop=$(( $top_start+$top_count ))
else
  top_start=$(( ($rank*$top_count)+$top_remainder ))
  top_stop=$(( $top_start+($top_count-1) ))
fi

# Store time files directories in an array
cd $target_dir
shopt -s nullglob
FILES=(*)

# Generate a list of local, top-level files & dirs to tar up
mpi_barrier
for ((i=top_start; i<=top_stop; ++i)); do
  echo ${FILES[$i]} >> $target_dir/rank${rank}_filelist$$
done
tar -cf $target_dir/rank${rank}.tar -C $target_dir -T $target_dir/rank${rank}_filelist$$

# Synchronize and do some cleanup
mpi_barrier
for ((i=top_start; i<=top_stop; ++i)); do
  # We're assuming there aren't massive amounts of files in the top-level directory
  # so using a standard rm command instead of Lustre-friendly munlink
  rm -rf $target_dir/${FILES[$i]}
done
rm rank${rank}_filelist$$

# Let process 0 handle the final tar
mpi_barrier
if [ $rank -eq 0 ]; then
  archive="$(basename $target_dir)"
  top_dir="$(dirname "$target_dir")"
  tar -cf $top_dir/$archive.tar -C $top_dir $archive
  find $target_dir -type f -print0 | xargs -0 munlink
  find $target_dir -depth -type d -empty -delete
  rm -rf $target_dir

  echo "$target_dir successfully archived at $top_dir/$archive.tar"
fi

mpi_finalize
