"use client";

import { useLayoutEffect } from "react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

gsap.registerPlugin(ScrollTrigger);

/**
 * GSAP entrance layer for the home page. Runs after hydration but before the
 * first paint, so nothing flashes. When reduced motion is set, it does
 * nothing and every element stays visible.
 */
export function HomeMotion() {
  useLayoutEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    const ctx = gsap.context(() => {
      gsap.set("[data-anim='hero']", {
        autoAlpha: 0,
        y: 18,
        filter: "blur(5px)",
      });

      const intro = gsap.timeline({ defaults: { ease: "power3.out" } });
      intro
        .to("[data-anim='hero']", {
          autoAlpha: 1,
          y: 0,
          filter: "blur(0px)",
          duration: 0.7,
          stagger: 0.08,
        })
        .fromTo(
          "[data-anim='card']",
          { autoAlpha: 0, y: 26, scale: 0.985 },
          { autoAlpha: 1, y: 0, scale: 1, duration: 0.85 },
          0.12
        );

      gsap.from("[data-anim='head']", {
        autoAlpha: 0,
        y: 12,
        duration: 0.5,
        ease: "power2.out",
        stagger: 0.05,
        scrollTrigger: {
          trigger: "[data-anim='start']",
          start: "top 82%",
          once: true,
        },
      });

      gsap.from("[data-anim='tile']", {
        autoAlpha: 0,
        y: 16,
        duration: 0.55,
        stagger: 0.06,
        delay: 0.08,
        ease: "power2.out",
        scrollTrigger: {
          trigger: "[data-anim='start']",
          start: "top 82%",
          once: true,
        },
      });

      gsap.from("[data-anim='foot'] > *", {
        autoAlpha: 0,
        y: 8,
        duration: 0.45,
        stagger: 0.04,
        ease: "power2.out",
        scrollTrigger: {
          trigger: "[data-anim='foot']",
          start: "top 92%",
          once: true,
        },
      });
    });

    return () => ctx.revert();
  }, []);

  return null;
}
