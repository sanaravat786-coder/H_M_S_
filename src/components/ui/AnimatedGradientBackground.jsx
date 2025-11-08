import React from 'react';

const AnimatedGradientBackground = () => {
    return (
        <div className="absolute inset-0 z-0">
            <div className="absolute inset-0 bg-gradient-to-br from-primary to-accent bg-[length:400%_400%] animate-gradient"></div>
        </div>
    );
};

export default AnimatedGradientBackground;
