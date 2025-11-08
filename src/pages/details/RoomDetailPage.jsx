import React, { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import DetailPageLayout from '../../components/layout/DetailPageLayout';
import DetailItem from '../../components/ui/DetailItem';
import { Loader } from 'lucide-react';
import toast from 'react-hot-toast';

const statusStyles = {
    Occupied: 'bg-red-500/10 text-red-500 dark:bg-red-500/20 dark:text-red-400',
    Vacant: 'bg-green-500/10 text-green-600 dark:bg-green-500/20 dark:text-green-400',
    Maintenance: 'bg-yellow-500/10 text-yellow-600 dark:bg-yellow-500/20 dark:text-yellow-400',
};

const RoomDetailPage = () => {
    const { id } = useParams();
    const [room, setRoom] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        const fetchRoom = async () => {
            if (!id) return;
            setLoading(true);
            const { data, error } = await supabase
                .from('rooms')
                .select('*')
                .eq('id', id)
                .single();

            if (error || !data) {
                toast.error('Room not found.');
                console.error(error);
            } else {
                setRoom(data);
            }
            setLoading(false);
        };

        fetchRoom();
    }, [id]);

    if (loading) {
        return <div className="flex justify-center items-center h-64"><Loader className="animate-spin h-8 w-8 text-primary" /></div>;
    }

    if (!room) {
        return <div className="text-center text-base-content-secondary dark:text-dark-base-content-secondary">Room not found</div>;
    }

    return (
        <DetailPageLayout title={`Room ${room.room_number}`} backTo="/rooms">
            <DetailItem label="Room Number" value={room.room_number} />
            <DetailItem label="Room Type" value={room.type} />
            <DetailItem label="Status">
                <span className={`px-2.5 py-0.5 inline-flex text-xs leading-5 font-semibold rounded-full ${statusStyles[room.status]}`}>
                    {room.status}
                </span>
            </DetailItem>
            <DetailItem label="Occupants" value={room.occupants} />
        </DetailPageLayout>
    );
};

export default RoomDetailPage;
