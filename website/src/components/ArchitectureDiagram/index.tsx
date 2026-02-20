import React from 'react';
import styles from './styles.module.css';

const Arrow = ({ label }: { label?: string }) => (
  <div className={styles.arrow}>
    {label && <span>{label}</span>}
    <div className={styles.arrowIcon}>↓</div>
  </div>
);

export default function ArchitectureDiagram() {
  return (
    <div className={styles.diagramContainer}>
      <div className={styles.layer}>
        <div className={styles.layerTitle}>Dart & Flutter Application Layer</div>
        <div className={styles.nodesRow}>
          <div className={styles.node}>
            <span className={styles.nodeIcon}>📱</span>
            <div className={styles.nodeTitle}>
              Flutter UI
              <span className={styles.nodeSub}>Application State</span>
            </div>
          </div>
        </div>
        
        <Arrow label="State Streams" />
        
        <div className={styles.nodesRow}>
          <div className={styles.nodeAccent}>
            <span className={styles.nodeIcon}>⚙️</span>
            <div className={styles.nodeTitle}>
              LlamaEngine
              <span className={styles.nodeSub}>Dart Core API</span>
            </div>
          </div>
        </div>
        
        <Arrow label="Async Tasks" />
        
        <div className={styles.nodesRow}>
          <div className={styles.node}>
            <span className={styles.nodeIcon}>🔄</span>
            <div className={styles.nodeTitle}>
              Dart Isolate
              <span className={styles.nodeSub}>Worker Thread</span>
            </div>
          </div>
        </div>
      </div>

      <div className={styles.bridgeGroup}>
        <Arrow label="Native Calls" />
        <div className={styles.bridgeNode}>
          <span className={styles.nodeIcon}>🌉</span>
          <div className={styles.nodeTitle}>Dart FFI Bridge</div>
        </div>
        <Arrow label="C-API" />
      </div>

      <div className={styles.layer}>
        <div className={styles.layerTitle}>Native llama.cpp & GGML Layer</div>
        <div className={styles.nodesRow}>
          <div className={styles.node}>
            <span className={styles.nodeIcon}>📚</span>
            <div className={styles.nodeTitle}>
              Common Library
              <span className={styles.nodeSub}>mmap, sampling</span>
            </div>
          </div>
        </div>
        
        <Arrow />
        
        <div className={styles.nodesRow}>
          <div className={styles.nodeAccent}>
            <span className={styles.nodeIcon}>🧠</span>
            <div className={styles.nodeTitle}>
              llama.cpp Core
              <span className={styles.nodeSub}>Inference Engine</span>
            </div>
          </div>
        </div>
        
        <Arrow />
        
        <div className={styles.nodesRow}>
          <div className={styles.node}>
            <span className={styles.nodeIcon}>🧮</span>
            <div className={styles.nodeTitle}>
              GGML Math Backend
              <span className={styles.nodeSub}>Tensor Operations</span>
            </div>
          </div>
        </div>
      </div>

      <div className={styles.splitArrows}>
        <div className={styles.splitArrowLeft}>
          <span>↙</span> Vectorized
        </div>
        <div className={styles.splitArrowRight}>
          Compute <span>↘</span>
        </div>
      </div>

      <div className={styles.layer}>
        <div className={styles.layerTitle}>Hardware Compute</div>
        <div className={styles.nodesRowHardware}>
          <div className={styles.nodeHardware}>
            <span className={styles.nodeIcon}>🖥️</span>
            <div className={styles.nodeTitle}>
              CPU Intrinsics
              <span className={styles.nodeSub}>NEON, AVX</span>
            </div>
          </div>
          <div className={styles.nodeHardware}>
            <span className={styles.nodeIcon}>🎮</span>
            <div className={styles.nodeTitle}>
              GPU Acceleration
              <span className={styles.nodeSub}>Metal / Vulkan / CUDA</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
