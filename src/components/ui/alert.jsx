import React from 'react';

const alertVariants = {
  default: "bg-base-200 dark:bg-dark-base-300 text-base-content dark:text-dark-base-content",
  destructive: "bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-300 border-red-300 dark:border-red-700",
  success: "bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-300 border-green-300 dark:border-green-700",
};

export const Alert = ({ className, variant = 'default', ...props }) => (
  <div
    role="alert"
    className={`relative w-full rounded-lg border p-4 [&>svg~*]:pl-7 [&>svg+div]:translate-y-[-3px] [&>svg]:absolute [&>svg]:left-4 [&>svg]:top-4 [&>svg]:text-foreground ${alertVariants[variant]} ${className}`}
    {...props}
  />
);

export const AlertTitle = ({ className, ...props }) => (
  <h5
    className={`mb-1 font-medium leading-none tracking-tight ${className}`}
    {...props}
  />
);

export const AlertDescription = ({ className, ...props }) => (
  <div
    className={`text-sm [&_p]:leading-relaxed ${className}`}
    {...props}
  />
);
