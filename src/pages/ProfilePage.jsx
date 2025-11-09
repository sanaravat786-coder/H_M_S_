import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../context/AuthContext';
import { supabase } from '../lib/supabase';
import toast from 'react-hot-toast';
import { User, Mail, Phone, BookOpen, BedDouble, Calendar, Edit, KeyRound, Loader } from 'lucide-react';
import EditProfileModal from '../components/profile/EditProfileModal';
import ChangePasswordModal from '../components/profile/ChangePasswordModal';

const ProfileInfoItem = ({ icon, label, value }) => (
    <div className="flex items-start py-4">
        <div className="p-2 bg-primary/10 text-primary rounded-full mr-4 flex-shrink-0">
            {icon}
        </div>
        <div className="min-w-0 flex-1">
            <p className="text-sm text-base-content-secondary dark:text-dark-base-content-secondary">{label}</p>
            <p className="font-semibold text-base-content dark:text-dark-base-content break-words">{value || 'N/A'}</p>
        </div>
    </div>
);

const ProfilePage = () => {
    const { user } = useAuth();
    const [profile, setProfile] = useState(null);
    const [loading, setLoading] = useState(true);
    const [isEditModalOpen, setIsEditModalOpen] = useState(false);
    const [isPasswordModalOpen, setIsPasswordModalOpen] = useState(false);

    const fetchProfile = useCallback(async () => {
        if (!user) return;
        setLoading(true);
        try {
            const { data: profileData, error: profileError } = await supabase
                .from('profiles')
                .select('*')
                .eq('id', user.id)
                .single();

            if (profileError) throw profileError;

            let finalProfile = {
                ...profileData,
                email: user.email,
                role: user.user_metadata.role,
                room_number: 'N/A'
            };

            if (finalProfile.role === 'Student') {
                const { data: allocationData, error: allocationError } = await supabase
                    .from('room_allocations')
                    .select('rooms(room_number)')
                    .eq('student_id', user.id)
                    .eq('is_active', true)
                    .maybeSingle();
                
                if (!allocationError && allocationData && allocationData.rooms) {
                    finalProfile.room_number = allocationData.rooms.room_number;
                }
            }
            
            setProfile(finalProfile);

        } catch (error) {
            toast.error('Failed to fetch profile details.');
            console.error("Profile fetch error:", error);
        } finally {
            setLoading(false);
        }
    }, [user]);

    useEffect(() => {
        if (user) {
            fetchProfile();
        }
    }, [user, fetchProfile]);

    if (loading) {
        return <div className="flex justify-center items-center h-64"><Loader className="animate-spin h-8 w-8 text-primary" /></div>;
    }

    if (!profile) {
        return <div className="text-center">Could not load profile.</div>;
    }

    const getInitials = (name) => {
        if (!name) return '?';
        const names = name.split(' ');
        return names.length > 1 ? `${names[0][0]}${names[names.length - 1][0]}`.toUpperCase() : name.substring(0, 2).toUpperCase();
    };

    const joiningDate = profile.joining_date ? new Date(profile.joining_date) : new Date(profile.created_at);
    // Add timezone offset to prevent date from being off by one day
    joiningDate.setMinutes(joiningDate.getMinutes() + joiningDate.getTimezoneOffset());


    return (
        <>
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
                {/* Left Card: Profile Header */}
                <div className="lg:col-span-1 flex flex-col items-center text-center bg-base-100 dark:bg-dark-base-200 p-8 rounded-2xl shadow-lg">
                    <div className="w-32 h-32 mb-4 flex items-center justify-center rounded-full bg-primary/20 dark:bg-dark-primary/30 text-primary dark:text-dark-primary font-bold text-5xl">
                        {getInitials(profile.full_name)}
                    </div>
                    <h1 className="text-3xl font-bold font-heading">{profile.full_name}</h1>
                    <p className="text-base-content-secondary dark:text-dark-base-content-secondary">{profile.role}</p>
                    <div className="mt-8 w-full space-y-3">
                        <button onClick={() => setIsEditModalOpen(true)} className="w-full inline-flex items-center justify-center px-4 py-2 border border-transparent text-sm font-medium rounded-lg shadow-sm text-primary-content bg-primary hover:bg-primary-focus">
                            <Edit className="w-4 h-4 mr-2" /> Edit Profile
                        </button>
                        <button onClick={() => setIsPasswordModalOpen(true)} className="w-full inline-flex items-center justify-center px-4 py-2 border border-base-300 dark:border-dark-base-300 text-sm font-medium rounded-lg shadow-sm text-base-content dark:text-dark-base-content bg-base-100 dark:bg-dark-base-200 hover:bg-base-200 dark:hover:bg-dark-base-300">
                            <KeyRound className="w-4 h-4 mr-2" /> Change Password
                        </button>
                    </div>
                </div>

                {/* Right Card: Details */}
                <div className="lg:col-span-2 bg-base-100 dark:bg-dark-base-200 p-8 rounded-2xl shadow-lg">
                    <div>
                        <h2 className="text-xl font-bold mb-4">Personal Information</h2>
                        <div className="grid grid-cols-1 md:grid-cols-2 divide-y md:divide-y-0 md:divide-x divide-base-200 dark:divide-dark-base-300">
                            <div className="md:pr-6">
                                <ProfileInfoItem icon={<User size={20} />} label="Full Name" value={profile.full_name} />
                                <ProfileInfoItem icon={<Mail size={20} />} label="Email Address" value={profile.email} />
                            </div>
                            <div className="md:pl-6">
                                <ProfileInfoItem icon={<Phone size={20} />} label="Contact Number" value={profile.contact} />
                                {profile.role === 'Student' && <ProfileInfoItem icon={<BookOpen size={20} />} label="Course" value={profile.course} />}
                            </div>
                        </div>
                    </div>
                    <div className="mt-8">
                        <h2 className="text-xl font-bold mb-4">Hostel Details</h2>
                        <div className="grid grid-cols-1 md:grid-cols-2 divide-y md:divide-y-0 md:divide-x divide-base-200 dark:divide-dark-base-300">
                            <div className="md:pr-6">
                                {profile.role === 'Student' && <ProfileInfoItem icon={<BedDouble size={20} />} label="Room Number" value={profile.room_number} />}
                            </div>
                            <div className="md:pl-6">
                                <ProfileInfoItem icon={<Calendar size={20} />} label="Joined On" value={joiningDate.toLocaleDateString()} />
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <EditProfileModal
                isOpen={isEditModalOpen}
                onClose={() => setIsEditModalOpen(false)}
                profile={profile}
                onProfileUpdate={fetchProfile}
            />
            <ChangePasswordModal
                isOpen={isPasswordModalOpen}
                onClose={() => setIsPasswordModalOpen(false)}
            />
        </>
    );
};

export default ProfilePage;
