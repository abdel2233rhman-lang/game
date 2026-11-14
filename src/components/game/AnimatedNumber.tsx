import { useEffect, useRef, useState } from 'react';
import { animate } from 'framer-motion';

export function AnimatedNumber({ value }: { value: number }) {
  const [display, setDisplay] = useState(value);
  const fromRef = useRef(value);

  useEffect(() => {
    const controls = animate(fromRef.current, value, {
      duration: 0.8,
      ease: 'easeOut',
      onUpdate: (current) => setDisplay(Math.round(current)),
    });
    fromRef.current = value;
    return () => controls.stop();
  }, [value]);

  return <span className="tabular-nums">{display.toLocaleString('en-US')}</span>;
}
