"use client";

import { useEffect, useRef } from "react";
import * as THREE from "three";

export function ArenaFxLayer({ phase }: { phase: string }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    const parent = canvas?.parentElement;
    if (!canvas || !parent) return;

    const renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setClearColor(0x000000, 0);

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(45, 1, 0.1, 20);
    camera.position.set(0, 0, 7);

    const geometry = new THREE.BufferGeometry();
    const positions: number[] = [];
    for (let index = 0; index < 90; index += 1) {
      positions.push((Math.random() - 0.5) * 9, (Math.random() - 0.5) * 5, (Math.random() - 0.5) * 2);
    }
    geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));

    const material = new THREE.PointsMaterial({
      color: phase === "combat" ? "#ff8b35" : "#35c7ff",
      size: 0.045,
      transparent: true,
      opacity: 0.5
    });
    const particles = new THREE.Points(geometry, material);
    scene.add(particles);

    let animationFrame = 0;
    const resize = () => {
      const rect = parent.getBoundingClientRect();
      renderer.setSize(rect.width, rect.height, false);
      camera.aspect = rect.width / Math.max(rect.height, 1);
      camera.updateProjectionMatrix();
    };

    const animate = () => {
      animationFrame = requestAnimationFrame(animate);
      particles.rotation.z += 0.0008;
      particles.rotation.x = Math.sin(Date.now() / 1600) * 0.015;
      renderer.render(scene, camera);
    };

    resize();
    animate();
    const observer = new ResizeObserver(resize);
    observer.observe(parent);

    return () => {
      cancelAnimationFrame(animationFrame);
      observer.disconnect();
      geometry.dispose();
      material.dispose();
      renderer.dispose();
    };
  }, [phase]);

  return <canvas ref={canvasRef} className="arena-fx-canvas" aria-hidden="true" />;
}
