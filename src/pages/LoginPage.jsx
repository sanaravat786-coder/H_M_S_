import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Mail, Lock, Loader } from 'lucide-react';
import { supabase } from '../lib/supabase';
import toast from 'react-hot-toast';
import Logo from '../components/ui/Logo';
import AnimatedGradientBackground from '../components/ui/AnimatedGradientBackground';

const GoogleIcon = () => (
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 48 48">
        <path fill="#FFC107" d="M43.611,20.083H42V20H24v8h11.303c-1.649,4.657-6.08,8-11.303,8c-6.627,0-12-5.373-12-12c0-6.627,5.373-12,12-12c3.059,0,5.842,1.154,7.961,3.039l5.657-5.657C34.046,6.053,29.268,4,24,4C12.955,4,4,12.955,4,24s8.955,20,20,20s20-8.955,20-20C44,22.659,43.862,21.35,43.611,20.083z"></path>
        <path fill="#FF3D00" d="M6.306,14.691l6.571,4.819C14.655,15.108,18.961,12,24,12c3.059,0,5.842,1.154,7.961,3.039l5.657-5.657C34.046,6.053,29.268,4,24,4C16.318,4,9.656,8.337,6.306,14.691z"></path>
        <path fill="#4CAF50" d="M24,44c5.166,0,9.86-1.977,13.409-5.192l-6.19-5.238C29.211,35.091,26.715,36,24,36c-5.202,0-9.619-3.317-11.283-7.946l-6.522,5.025C9.505,39.556,16.227,44,24,44z"></path>
        <path fill="#1976D2" d="M43.611,20.083H42V20H24v8h11.303c-0.792,2.237-2.231,4.166-4.087,5.571l6.19,5.238C42.012,35.83,44,30.138,44,24C44,22.659,43.862,21.35,43.611,20.083z"></path>
    </svg>
);

function LoginPage() {
    const navigate = useNavigate();
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [loading, setLoading] = useState(false);

    const handleLogin = async (e) => {
        e.preventDefault();
        setLoading(true);

        const { error } = await supabase.auth.signInWithPassword({
            email,
            password,
        });

        if (error) {
            toast.error(error.message);
        } else {
            toast.success('Logged in successfully!');
            navigate('/');
        }
        setLoading(false);
    };

    return (
        <div className="min-h-screen bg-base-100 dark:bg-dark-base-100 flex transition-colors">
            <div className="hidden lg:flex w-1/2 relative items-center justify-center overflow-hidden">
                <AnimatedGradientBackground />
                <div className="relative z-10 text-center text-white p-8">
                    <h1 className="text-5xl font-heading font-bold mb-4">Hostel Management System</h1>
                    <p className="text-lg text-gray-200">
                        Efficiently manage your hostel operations with our comprehensive solution.
                    </p>
                </div>
            </div>

            <div className="w-full lg:w-1/2 flex items-center justify-center p-6 sm:p-12">
                <div className="w-full max-w-md">
                    <div className="text-center mb-10">
                        <div className="flex justify-center mb-4">
                            <Logo className="h-12 text-primary dark:text-dark-primary" />
                        </div>
                        <h2 className="text-3xl font-bold font-heading text-base-content dark:text-dark-base-content">Login to your account</h2>
                        <p className="text-base-content-secondary dark:text-dark-base-content-secondary mt-2">Welcome back! Please enter your details.</p>
                    </div>

                    <form className="space-y-6" onSubmit={handleLogin}>
                        <div>
                            <label htmlFor="email" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">
                                Email
                            </label>
                            <div className="mt-1 relative rounded-md shadow-sm">
                                <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                                    <Mail className="h-5 w-5 text-gray-400" />
                                </div>
                                <input
                                    type="email"
                                    name="email"
                                    id="email"
                                    value={email}
                                    onChange={(e) => setEmail(e.target.value)}
                                    className="block w-full rounded-lg border-base-300 dark:border-dark-base-300 bg-base-200 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content pl-10 py-3 focus:border-primary dark:focus:border-dark-primary focus:ring-primary dark:focus:ring-dark-primary sm:text-sm"
                                    placeholder="you@example.com"
                                    required
                                />
                            </div>
                        </div>

                        <div>
                            <label htmlFor="password" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">
                                Password
                            </label>
                            <div className="mt-1 relative rounded-md shadow-sm">
                                <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                                    <Lock className="h-5 w-5 text-gray-400" />
                                </div>
                                <input
                                    type="password"
                                    name="password"
                                    id="password"
                                    value={password}
                                    onChange={(e) => setPassword(e.target.value)}
                                    className="block w-full rounded-lg border-base-300 dark:border-dark-base-300 bg-base-200 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content pl-10 py-3 focus:border-primary dark:focus:border-dark-primary focus:ring-primary dark:focus:ring-dark-primary sm:text-sm"
                                    placeholder="••••••••"
                                    required
                                />
                            </div>
                        </div>

                        <div className="flex items-center justify-between">
                            <div className="flex items-center">
                                <input id="remember-me" name="remember-me" type="checkbox" className="h-4 w-4 rounded border-base-300 dark:border-dark-base-300 text-primary focus:ring-primary" />
                                <label htmlFor="remember-me" className="ml-2 block text-sm text-base-content dark:text-dark-base-content">
                                    Remember me
                                </label>
                            </div>
                            <div className="text-sm">
                                <a href="#" className="font-medium text-primary hover:text-primary-focus dark:text-dark-primary dark:hover:text-dark-primary-focus">
                                    Forgot Password?
                                </a>
                            </div>
                        </div>

                        <div>
                            <button
                                type="submit"
                                disabled={loading}
                                className="group relative flex w-full justify-center rounded-lg border border-transparent bg-primary py-3 px-4 text-sm font-medium text-primary-content hover:bg-primary-focus focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2 disabled:bg-primary/70 dark:bg-dark-primary dark:hover:bg-dark-primary-focus dark:focus:ring-dark-primary dark:focus:ring-offset-dark-base-100 transition-all duration-300 transform hover:scale-105"
                            >
                                {loading && <Loader className="animate-spin h-5 w-5 mr-3" />}
                                {loading ? 'Logging in...' : 'Login'}
                            </button>
                        </div>
                    </form>

                    <div className="mt-6">
                        <div className="relative">
                            <div className="absolute inset-0 flex items-center">
                                <div className="w-full border-t border-base-300 dark:border-dark-base-300" />
                            </div>
                            <div className="relative flex justify-center text-sm">
                                <span className="bg-base-100 dark:bg-dark-base-100 px-2 text-base-content-secondary dark:text-dark-base-content-secondary">Or continue with</span>
                            </div>
                        </div>

                        <div className="mt-6">
                            <a
                                href="#"
                                className="w-full inline-flex justify-center items-center py-3 px-4 border border-base-300 dark:border-dark-base-300 rounded-lg shadow-sm bg-base-100 dark:bg-dark-base-200 text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary hover:bg-base-200 dark:hover:bg-dark-base-300"
                            >
                                <GoogleIcon />
                                <span className="ml-3">Sign in with Google</span>
                            </a>
                        </div>
                    </div>

                    <p className="mt-8 text-center text-sm text-base-content-secondary dark:text-dark-base-content-secondary">
                        Don't have an account?{' '}
                        <Link to="/signup" className="font-medium text-primary hover:text-primary-focus dark:text-dark-primary dark:hover:text-dark-primary-focus">
                            Sign Up
                        </Link>
                    </p>
                </div>
            </div>
        </div>
    );
}

export default LoginPage;
