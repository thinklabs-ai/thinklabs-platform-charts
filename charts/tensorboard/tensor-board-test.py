#!/usr/bin/env python3
"""
Generate sample TensorBoard event files for testing with Azure Blob Storage
"""

import os
from datetime import datetime
from pathlib import Path

try:
    from tensorboard.plugins.scalar import metadata as scalar_metadata
    from tensorboard.compat.proto import summary_pb2
    from tensorboard.compat.proto import event_pb2
    import tensorflow as tf
except ImportError:
    print("Installing required packages...")
    os.system("pip install tensorboard tensorflow protobuf")
    from tensorboard.plugins.scalar import metadata as scalar_metadata
    from tensorboard.compat.proto import summary_pb2
    from tensorboard.compat.proto import event_pb2
    import tensorflow as tf


def create_sample_events(log_dir="sample_logs"):
    """Create sample TensorBoard event files"""

    # Create log directory
    Path(log_dir).mkdir(exist_ok=True)

    # Create event file
    event_file = os.path.join(log_dir, f"events.out.tfevents.{int(datetime.now().timestamp())}")

    with tf.io.gfile.GFile(event_file, "wb") as f:
        # Write file version
        f.write(b"brain.Event:2\n")

    # Create writer
    writer = tf.summary.create_file_writer(log_dir)

    with writer.as_default():
        # Write sample scalars (training metrics)
        for step in range(1, 101):
            # Loss
            tf.summary.scalar('loss', 10.0 / (step + 1), step=step)

            # Accuracy
            tf.summary.scalar('accuracy', 0.5 + 0.4 * (1 - 1 / (step + 1)), step=step)

            # Learning rate
            tf.summary.scalar('learning_rate', 0.001 * (0.95 ** (step / 10)), step=step)

            # Training time per step
            tf.summary.scalar('train_time_per_step_ms', 50 + 5 * (step % 10), step=step)

            writer.flush()

    writer.close()
    print(f"✓ Sample TensorBoard logs created in: {log_dir}")
    print(f"  Event file: {event_file}")
    return log_dir


def create_sample_text_logs(log_dir="sample_logs"):
    """Create sample text logs for reference"""

    Path(log_dir).mkdir(exist_ok=True)

    log_file = os.path.join(log_dir, "training_log.txt")

    with open(log_file, "w") as f:
        f.write("=" * 60 + "\n")
        f.write("TensorBoard Sample Training Log\n")
        f.write("=" * 60 + "\n")
        f.write(f"Generated: {datetime.now().isoformat()}\n")
        f.write(f"Model: Sample Neural Network\n")
        f.write(f"Dataset: MNIST\n\n")

        f.write("Training Progress:\n")
        f.write("-" * 60 + "\n")
        f.write(f"{'Step':<10} {'Loss':<15} {'Accuracy':<15} {'LR':<15}\n")
        f.write("-" * 60 + "\n")

        for step in range(1, 101, 10):
            loss = 10.0 / (step + 1)
            accuracy = 0.5 + 0.4 * (1 - 1 / (step + 1))
            lr = 0.001 * (0.95 ** (step / 10))
            f.write(f"{step:<10} {loss:<15.6f} {accuracy:<15.4f} {lr:<15.8f}\n")

        f.write("-" * 60 + "\n")
        f.write("Training completed successfully!\n")

    print(f"✓ Sample text log created: {log_file}")
    return log_file


def main():
    print("\n🚀 TensorBoard Sample Log Generator\n")

    # Create sample logs
    log_dir = create_sample_events()
    log_file = create_sample_text_logs(log_dir)

    print("\n📋 Next Steps:")
    print(f"1. Upload the '{log_dir}' directory to Azure Blob Storage:")
    print(f"   az storage blob upload-batch \\")
    print(f"     -d mlflow-artifacts \\")
    print(f"     -s {log_dir} \\")
    print(f"     --account-name thinklabsmlflow \\")
    print(f"     --account-key '<your-account-key>'")
    print(f"\n2. Or use the Azure Storage Explorer GUI to upload the folder")
    print(f"\n3. Test TensorBoard with:")
    print(f"   tensorboard --logdir={log_dir}")
    print(f"\n4. Visit http://localhost:6006 to view the logs")
    print(f"\n5. Once deployed on AKS, the logs will be read from:")
    print(f"   https://thinklabsmlflow.blob.core.windows.net/mlflow-artifacts/{log_dir}")


if __name__ == "__main__":
    main()
