import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { User, Mail, Lock, Users, Loader } from 'lucide-react';
import { supabase } from '../lib/supabase';
import toast from 'react-hot-toast';
import Logo from '../components/ui/Logo';
import AnimatedGradientBackground from '../components/ui/AnimatedGradientBackground';

function SignUpPage() {
    const navigate = useNavigate();
    const [fullName, setFullName] = useState('');
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [role, setRole] = useState('Student');
    const [loading, setLoading] = useState(false);

    const handleSignUp = async (e) => {
        e.preventDefault();
        setLoading(true);

        const { data, error } = await supabase.auth.signUp({
            email,
            password,
            options: {
                data: {
                    full_name: fullName,
                    role: role,
                },
                emailRedirectTo: `${window.location.origin}/`
            }
        });

        if (error) {
            toast.error(error.message);
        } else if (data.user && data.user.identities && data.user.identities.length === 0) {
            toast.error('User with this email already exists.');
        } else {
            toast.success('Registration successful! Please check your email to verify your account.');
            navigate('/login');
        }

        setLoading(false);
    };

    return (
        <div className="min-h-screen bg-base-100 dark:bg-dark-base-100 flex transition-colors">
            <div className="hidden lg:flex w-1/2 relative items-center justify-center overflow-hidden">
                <AnimatedGradientBackground />
                <div className="relative z-10 text-center text-white p-8">
                    <h1 className="text-5xl font-heading font-bold mb-4">Join Our Community</h1>
                    <p className="text-lg text-gray-200">
                        Create an account to get started with the best hostel experience.
                    </p>
                </div>
            </div>

            <div className="w-full lg:w-1/2 flex items-center justify-center p-6 sm:p-12">
                <div className="w-full max-w-md">
                    <div className="text-center mb-10">
                         <div className="flex justify-center mb-4">
                            <Logo className="h-12 text-primary dark:text-dark-primary" />
                        </div>
                        <h2 className="text-3xl font-bold font-heading text-base-content dark:text-dark-base-content">Create an account</h2>
                        <p className="text-base-content-secondary dark:text-dark-base-content-secondary mt-2">Let's get you set up.</p>
                    </div>

                    <form className="space-y-6" onSubmit={handleSignUp}>
                        <div>
                            <label htmlFor="fullName" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">
                                Full Name
                            </label>
                            <div className="mt-1 relative rounded-md shadow-sm">
                                <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                                    <User className="h-5 w-5 text-gray-400" />
                                </div>
                                <input
                                    type="text"
                                    name="fullName"
                                    id="fullName"
                                    value={fullName}
                                    onChange={(e) => setFullName(e.target.value)}
                                    className="block w-full rounded-lg border-base-300 dark:border-dark-base-300 bg-base-200 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content pl-10 py-3 focus:border-primary dark:focus:border-dark-primary focus:ring-primary dark:focus:ring-dark-primary sm:text-sm"
                                    placeholder="John Doe"
                                    required
                                />
                            </div>
                        </div>

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

                        <div>
                            <label htmlFor="role" className="block text-sm font-medium text-base-content-secondary dark:text-dark-base-content-secondary">
                                I am a...
                            </label>
                            <div className="mt-1 relative rounded-md shadow-sm">
                                <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                                    <Users className="h-5 w-5 text-gray-400" />
                                </div>
                                <select
                                    id="role"
                                    name="role"
                                    value={role}
                                    onChange={(e) => setRole(e.target.value)}
                                    className="block w-full rounded-lg border-base-300 dark:border-dark-base-300 bg-base-200 dark:bg-dark-base-200 text-base-content dark:text-dark-base-content pl-10 py-3 focus:border-primary dark:focus:border-dark-primary focus:ring-primary dark:focus:ring-dark-primary sm:text-sm"
                                >
                                    <option>Admin</option>
                                    <option>Student</option>
                                    <option>Staff</option>
                                </select>
                            </div>
                        </div>

                        <div>
                            <button
                                type="submit"
                                disabled={loading}
                                className="group relative flex w-full justify-center rounded-lg border border-transparent bg-primary py-3 px-4 text-sm font-medium text-primary-content hover:bg-primary-focus focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2 disabled:bg-primary/70 dark:bg-dark-primary dark:hover:bg-dark-primary-focus dark:focus:ring-dark-primary dark:focus:ring-offset-dark-base-100 transition-all duration-300 transform hover:scale-105"
                            >
                                {loading && <Loader className="animate-spin h-5 w-5 mr-3" />}
                                {loading ? 'Creating Account...' : 'Create Account'}
                            </button>
                        </div>
                    </form>

                    <p className="mt-8 text-center text-sm text-base-content-secondary dark:text-dark-base-content-secondary">
                        Already have an account?{' '}
                        <Link to="/login" className="font-medium text-primary hover:text-primary-focus dark:text-dark-primary dark:hover:text-dark-primary-focus">
                            Login
                        </Link>
                    </p>
                </div>
            </div>
        </div>
    );
}

export default SignUpPage;
